//==============================================================================
// god_bot.xs - Age of Mythology: Retold God Bot
//
// A win-at-all-costs bot: it plays the Conqueror's slow, economy-heavy game but
// decides with information a human player cannot have. See docs/god-bot-design.md
// for the goal, the powers it exploits, and how each is translated into engine
// behaviour.
//==============================================================================
include "core/main.xs";

//==============================================================================
// Tunables
//==============================================================================
// Conqueror already attacks on a slow rhythm; we slow it down further.
const float cGodCadenceMultiplier = 1.5;

// Retreat: abandon an attack after losing this share of the army ...
const int cGodRetreatLossPercent = 50;
// ... within this many seconds, or when the enemy outnumbers us by this ratio.
const int cGodRetreatLossWindow = 45;
const int cGodRetreatEnemyRatioPercent = 150;

// Each attack carries its own loss sample, in two plan variables the engine leaves
// unused: its army power at the start of the loss window, and when that was.
const int cGodRetreatSamplePopVar = cAttackPlanUnused2;
const int cGodRetreatSampleTimeVar = cAttackPlanUnused4;

// A raid is a small group, so a whole base garrison counts as "outnumbered" and
// calls it off before it lands. Judge a raid only on the troops sitting on its
// target, and prefer the target the enemy is not sitting on.
const float cGodRaidTargetRadius = 30.0;
const float cGodRaidAbortRadius = 25.0;
// A party of eight cannot fight a garrison, so a site that is still guarded is
// not worth the walk. The bot counts the guard before it sends anyone.
const int cGodRaidMaxGuard = 2;

// A cavalry raid goes for the enemy's gold instead: a fast party that hits the
// mine the enemy is working and rides away. Cavalry outruns the defence, so the
// raid is judged by how close the enemy is rather than by how many of them there
// are, and only comes home once they are right on top of it.
const int cGodCavRaidMinCavalry = 4;
const float cGodCavRaidMineRadius = 30.0;
const float cGodCavRaidRetreatRadius = 20.0;

// The enemy's Titan: anything we send at a base while it is out feeds it, so call
// off an attack when it is this close, and only commit again with an army that
// can actually take one on.
const float cGodTitanFleeRadius = 45.0;
const int cGodTitanHuntArmyPop = 60;

// A Mythic game that has gone on this long with no age lead is a stalemate: the
// armies trade at the pop cap and the bank piles up. A Titan breaks it, so this is
// when the bot starts buying one.
const int cGodStalemateSeconds = 360;

// The Titan is paid from the bank, not from the engine's needs bookkeeping, which
// only reports a surplus long after the bank is full. Keep this share of the cost
// on top of it so the army keeps training.
const int cGodTitanReservePercent = 50;

// Decisive push: once we are clearly ahead, attack on a fast cadence instead.
const int cGodPushArmyPop = 40;   // military pop required before we commit
const int cGodPushInterval = 90;  // seconds between attacks while pushing
// The bot reads the enemy's army without scouting, so "clearly ahead" can mean
// this much more army power than theirs rather than a guess. Committing takes the
// full margin; staying committed only takes still being ahead, so a wobble around
// the threshold cannot flip the cadence back and forth.
const int cGodPushAdvantagePercent = 150;
const int cGodPushHoldPercent = 110;

// Economy: Conqueror-style boom target for the villager count.
const int cGodMaxVillagerPop = 90;

//==============================================================================
// Team games
//==============================================================================
// A 1v1 is one enemy to attack and one front to hold. A team game can put two or
// more enemies on our bases at once, or leave an ally about to be wiped out, and
// the 1v1 posture has no answer for either. The bot reads the game each second and
// picks one stance. A stance only ever leaves "normal" in a team game, so a 1v1
// runs the original code paths unchanged.
const int cGodStanceNormal = 0;
const int cGodStanceFortify = 1;
const int cGodStanceAssist = 2;

// An enemy player counts as pressing one of our bases once it has this much army
// power on it, so a scout or a lone villager does not read as a raid.
const float cGodThreatMinPower = 5.0;
// Troops gathered just outside a base's own radius still count as being on it.
const float cGodThreatExtraRadius = 20.0;

// Fortify once this many enemy players are pressing our bases at once ...
const int cGodFortifyEnemyPlayers = 2;
// ... or once the enemy on our bases outguns the army at home by this share. The
// power test needs a real force on the base, so a trickle does not tip it.
const int cGodFortifyThreatPercent = 100;
// Stay fortified until the bases have been quiet this long. Without it the stance
// flickers on and off as raiders step in and out of the base radius.
const int cGodFortifyQuietSeconds = 90;
// Towers per Town Center base while fortified. The engine's own number is about 2-3,
// which is thin when two or three players can hit different bases at once.
const int cGodFortifyTowersPerBase = 6;

// Pull the army back to our strongest base once the enemy on a base outguns it by
// this share ...
const int cGodFallbackRatioPercent = 150;
// ... and release the fallback once the enemy has dropped back to this share, or
// after this long. Two thresholds, so the army does not shuttle back and forth.
const int cGodFallbackReleasePercent = 100;
const int cGodFallbackHoldSeconds = 60;
// Weights for how defensible a base is. Towers and a Fortress matter most; houses
// are the least of it but still block and shelter.
const float cGodScoreTower = 3.0;
const float cGodScoreTownCenter = 5.0;
const float cGodScoreFortress = 6.0;
const float cGodScoreHouse = 0.5;
// The engine's primary land defend plan is priority 10, so anything above that pulls
// the army across to the fallback plan.
const int cGodFallbackPriority = 60;

//==============================================================================
// State
//==============================================================================
bool gGodNavalMap = false;
bool gGodPushing = false;
int gGodLastAge = -1;
bool gGodHeldTitanGate = false;
bool gGodStalemate = false;
int gGodMythicSince = -1;
bool gGodTitanReached = false;
int gGodRaidPlanID = -1;
bool gGodRaidIsCavalry = false;
int gGodEnemyCount = 0;
int gGodAllyCount = 0;
bool gGodTeamGame = false;
int gGodStance = cGodStanceNormal;
int gGodThreatBaseID = -1;
float gGodThreatPower = 0.0;
int gGodThreatPlayers = 0;
float gGodHomePower = 0.0;
int gGodLastThreatTime = -1;
int gGodFallbackPlanID = -1;
int gGodFallbackSince = -1;
int gGodFallbackFromBaseID = -1;

//==============================================================================
// Helpers
//==============================================================================

// A map only counts as naval if it is an island map or we start on a transport.
bool godIsNavalMap()
{
	if (gMapInfo.mIsIslandMap == true)
	{
		return true;
	}
	if (gMapInfo.mStartsWithTransport == true)
	{
		return true;
	}
	return false;
}

bool godUnderAttack()
{
	return gDefensivelyOverrun;
}

// Count the players still in the game. Gaia is player 0, so starting at 1 skips it;
// this is the loop the base game's chats.xs uses to total team scores. Players drop
// out as they are eliminated, so the caller refreshes this rather than caching it.
void godCountPlayers()
{
	gGodEnemyCount = 0;
	gGodAllyCount = 0;
	for (int i = 1; i <= cNumberPlayers; i++)
	{
		if (i == cMyID || kbPlayerHasLost(i) == true)
		{
			continue;
		}
		if (kbPlayerIsAlly(i) == true)
		{
			gGodAllyCount++;
		}
		else
		{
			gGodEnemyCount++;
		}
	}
	gGodTeamGame = gGodEnemyCount >= 2 || gGodAllyCount >= 1;
}

string godStanceName(int stance = cGodStanceNormal)
{
	if (stance == cGodStanceFortify)
	{
		return "fortify";
	}
	if (stance == cGodStanceAssist)
	{
		return "assist";
	}
	return "normal";
}

// Destroy every build plan for a given building type.
void godCancelBuildPlans(int puid = -1)
{
	int[] plans = aiPlanGetIDsByTypeAndVariableIntValue(cPlanBuild, cBuildPlanBuildingTypeID, puid);
	for (int i = 0; i < plans.size(); i++)
	{
		if (aiPlanGetIsIDValid(plans[i]) == true)
		{
			aiPlanDestroy(plans[i]);
		}
	}
}

bool godBaseHasMilitaryBuilding(int baseID = -1)
{
	for (int i = 0; i < gMilitaryBuildings.size(); i++)
	{
		int puid = gMilitaryBuildings[i];
		if (puid < 0)
		{
			continue;
		}
		if (getCountOfOwnAliveBuildingInBase(puid, baseID) >= 1)
		{
			return true;
		}
		if (getAmountBuildPlansInBase(puid, baseID) >= 1)
		{
			return true;
		}
	}
	return false;
}

int godPickMilitaryBuilding()
{
	for (int i = 0; i < gMilitaryBuildings.size(); i++)
	{
		int puid = gMilitaryBuildings[i];
		if (puid >= 0 && kbProtoUnitAvailable(puid) == true)
		{
			return puid;
		}
	}
	return -1;
}

// The next tower upgrade we can research right now, in the engine's own order.
int godNextTowerUpgrade()
{
	int watchTower = cTechWatchTower;
	int guardTower = cTechGuardTower;
	if (cMyCulture == cCultureAztec)
	{
		watchTower = cTechTzompantliWatchTower;
		guardTower = cTechTemiminaloyanTrials;
	}
	if (kbTechGetStatus(watchTower) == cTechStatusObtainable)
	{
		return watchTower;
	}
	if (kbTechGetStatus(cTechCrenellations) == cTechStatusObtainable)
	{
		return cTechCrenellations;
	}
	if (kbTechGetStatus(guardTower) == cTechStatusObtainable)
	{
		return guardTower;
	}
	if (cMyCulture == cCultureEgyptian && kbTechGetStatus(cTechBallistaTower) == cTechStatusObtainable)
	{
		return cTechBallistaTower;
	}
	if (cMyCulture == cCultureChinese && kbTechGetStatus(cTechCrossbowTower) == cTechStatusObtainable)
	{
		return cTechCrossbowTower;
	}
	return -1;
}

// How much enemy military is sitting on a point. The bot sees the whole map, so
// it never has to scout to know this.
int godEnemyMilitaryNear(vector location = cInvalidVector, float radius = 60.0)
{
	return getUnitCountByLocation(cUnitTypeLogicalTypeLandMilitary, cPlayerRelationEnemyNotGaia,
		cUnitStateAlive, location, radius);
}

// Combat power of a player's land military. A unit count treats a one-pop slinger
// and a four-pop hero alike, so the push decision is made on the power that
// actually decides the fight.
float godArmyPower(int playerID = -1)
{
	int queryID = useSimpleUnitQuery(cUnitTypeLogicalTypeLandMilitary, playerID, cUnitStateAlive);
	kbUnitQueryExecute(queryID);
	return kbUnitsGetPower(kbUnitQueryGetResults(queryID));
}

// Combat power of one player's land military around a point. The bot sees the whole
// map, so it never has to scout to know how much is sitting somewhere.
float godPowerNear(int player = cMyID, vector location = cInvalidVector, float radius = 60.0)
{
	int queryID = useSimpleUnitQuery(cUnitTypeLogicalTypeLandMilitary, player, cUnitStateAlive, location, radius);
	kbUnitQueryExecute(queryID);
	return kbUnitQueryGetPower(queryID);
}

// A base's own radius plus a margin, so troops massing just outside it still count
// as being on the base.
float godBaseThreatRadius(int baseID = -1)
{
	return kbBaseGetDistance(cMyID, baseID) + cGodThreatExtraRadius;
}

// Read the enemy pressure on every Town Center base we own, totalled and split by
// the player it belongs to. "Three raids from three players" then shows up as three
// players on our bases, instead of one global under-attack flag; the fortify stance
// and the fallback rule both decide from this. Refreshed once per strategy update.
void godUpdateThreat()
{
	gGodThreatBaseID = -1;
	gGodThreatPower = 0.0;
	gGodThreatPlayers = 0;
	gGodHomePower = 0.0;
	float worst = 0.0;
	int numBases = kbBaseGetNumber(cMyID);
	for (int i = 0; i < numBases; i++)
	{
		int baseID = kbBaseGetIDByIndex(cMyID, i);
		if (kbBaseIsFlagSet(cMyID, baseID, cBaseFlagTownCenter) == false)
		{
			continue;
		}
		vector loc = kbBaseGetLocation(cMyID, baseID);
		float radius = godBaseThreatRadius(baseID);
		float enemy = godPowerNear(cPlayerRelationEnemyNotGaia, loc, radius);
		gGodThreatPower = gGodThreatPower + enemy;
		gGodHomePower = gGodHomePower + godPowerNear(cMyID, loc, radius);
		if (enemy > worst)
		{
			worst = enemy;
			gGodThreatBaseID = baseID;
		}
	}
	for (int i = 1; i <= cNumberPlayers; i++)
	{
		if (i == cMyID || kbPlayerHasLost(i) == true || kbPlayerIsAlly(i) == true)
		{
			continue;
		}
		for (int j = 0; j < numBases; j++)
		{
			int baseID = kbBaseGetIDByIndex(cMyID, j);
			if (kbBaseIsFlagSet(cMyID, baseID, cBaseFlagTownCenter) == false)
			{
				continue;
			}
			if (godPowerNear(i, kbBaseGetLocation(cMyID, baseID), godBaseThreatRadius(baseID)) >= cGodThreatMinPower)
			{
				gGodThreatPlayers++;
				break;
			}
		}
	}
}

// Prefer the enemy drop site the enemy can least defend; fall back to any
// villager. The bot counts the troops at each one without scouting them, and
// refuses a site a party of eight would have to walk into a garrison to reach.
int godFindRaidTarget(int target = -1)
{
	int[] dropSites = new int(4, -1);
	dropSites[0] = cUnitTypeStorehouse;
	dropSites[1] = cUnitTypeGranary;
	dropSites[2] = cUnitTypeLumberCamp;
	dropSites[3] = cUnitTypeOxCartBuilding;
	int bestUnit = -1;
	int bestGuard = 0;
	for (int i = 0; i < dropSites.size(); i++)
	{
		int unitID = getUnit(dropSites[i], target, cUnitStateAlive);
		if (unitID == -1)
		{
			continue;
		}
		int guard = godEnemyMilitaryNear(kbUnitGetPosition(unitID), cGodRaidTargetRadius);
		if (bestUnit == -1 || guard < bestGuard)
		{
			bestUnit = unitID;
			bestGuard = guard;
		}
	}
	if (bestUnit == -1)
	{
		bestUnit = getUnit(cUnitTypeAbstractVillager, target, cUnitStateAlive);
		if (bestUnit == -1)
		{
			return -1;
		}
		bestGuard = godEnemyMilitaryNear(kbUnitGetPosition(bestUnit), cGodRaidTargetRadius);
	}
	if (bestGuard > cGodRaidMaxGuard)
	{
		return -1;
	}
	return bestUnit;
}

// Enemy villagers working a point. The bot sees the whole map, so it never has to
// scout to know where the enemy's gold is.
int godEnemyVillagersNear(vector location = cInvalidVector, float radius = 60.0)
{
	return getUnitCountByLocation(cUnitTypeAbstractVillager, cPlayerRelationEnemyNotGaia,
		cUnitStateAlive, location, radius);
}

// The enemy gold mine with the most miners on it, or -1. Mines belong to Gaia, not
// to the enemy, so player 0 is the right owner to ask for.
int godFindGoldMineTarget()
{
	int[] mineTypes = new int(3, -1);
	mineTypes[0] = cUnitTypeMineGoldSmall;
	mineTypes[1] = cUnitTypeMineGoldMedium;
	mineTypes[2] = cUnitTypeMineGoldLarge;
	int bestUnit = -1;
	int bestMiners = 0;
	for (int i = 0; i < mineTypes.size(); i++)
	{
		int unitID = getUnit(mineTypes[i], 0, cUnitStateAlive);
		if (unitID == -1)
		{
			continue;
		}
		int miners = godEnemyVillagersNear(kbUnitGetPosition(unitID), cGodCavRaidMineRadius);
		if (miners > bestMiners)
		{
			bestUnit = unitID;
			bestMiners = miners;
		}
	}
	return bestUnit;
}

// The enemy's Titan, if one is alive.
int godEnemyTitanID()
{
	int target = aiGetMostHatedPlayerID();
	if (target == -1)
	{
		return -1;
	}
	return getUnit(cUnitTypeAbstractTitan, target, cUnitStateAlive);
}

// Only one raid of either kind runs at a time.
bool godRaidInField()
{
	return aiPlanGetIsIDValid(gGodRaidPlanID);
}

// Set a raid up like the engine's own attacks: keep builders home, let god powers
// support it, and stop other plans pulling its units away. This owns the raid slot,
// so the caller only has to pick a target.
void godLaunchRaid(string name = "", vector point = cInvalidVector, int unitType = -1,
	int wantCount = 0, int maxCount = 0, int gatherWaitSeconds = 0, bool cavalry = false)
{
	vector gatherPoint = aiPlanGetVariableVector(gPrimaryLandDefendPlan, cDefendPlanGatherPoint, 0);
	int planID = aiPlanCreate(name, cPlanAttack, -1, gMilitaryAttackingCategoryID);
	aiPlanSetVariableInt(planID, cAttackPlanTargetMode, 0, cAttackPlanTargetModePoint);
	aiPlanSetVariableVector(planID, cAttackPlanTargetPoint, 0, point);
	aiPlanSetVariableVector(planID, cAttackPlanGatherPoint, 0, gatherPoint);
	aiPlanSetVariableFloat(planID, cAttackPlanGatherDistance, 0, 15.0);
	aiPlanSetVariableInt(planID, cAttackPlanGatherWaitTime, 0, gatherWaitSeconds * 1000);
	aiPlanSetVariableInt(planID, cAttackPlanDoneMode, 0, cAttackPlanDoneModeNoTarget | cAttackPlanDoneModeNoUnits);
	aiPlanAddUnitType(planID, unitType, 2, wantCount, maxCount);
	preventSomeBuildersFromJoiningAttack(planID);
	setDefaultAttackPlanTargetUnitTypes(planID);
	addPlanToAllSuitableGodpowerPlans(planID);
	aiPlanSetPriority(planID, 70);
	aiPlanSetFlag(planID, cPlanFlagCantBeStolenFrom, true);
	gGodRaidPlanID = planID;
	gGodRaidIsCavalry = cavalry;
}

// A Titan counts as one enemy unit, so the outnumbered check never sees it coming.
bool godTitanNear(vector location = cInvalidVector)
{
	return getUnitCountByLocation(cUnitTypeAbstractTitan, cPlayerRelationEnemyNotGaia,
		cUnitStateAlive, location, cGodTitanFleeRadius) > 0;
}

// The patient rhythm: Conqueror's attack interval by difficulty, slowed further.
int godSlowInterval()
{
	return xsFloatToInt(selectByDifficultyFloat(20, 15, 9, 7, 5, 5) * 60.0 * cGodCadenceMultiplier);
}

// The rhythm the bot is on right now: the fast one while pushing, the patient one
// otherwise.
int godCadenceInterval()
{
	if (gGodPushing == true)
	{
		return cGodPushInterval;
	}
	return godSlowInterval();
}

// Is this attack bleeding out, outnumbered, or standing in front of a Titan?
bool godAttackIsLosing(int planID = -1, int ourCount = 0, int ourPop = 0, int samplePop = 0)
{
	vector planLoc = aiPlanGetLocation(planID);
	if (planLoc == cInvalidVector)
	{
		return false;
	}
	// A Titan kills an army faster than the loss window can notice it.
	if (godTitanNear(planLoc) == true)
	{
		aiEcho("[GodBot] Retreating " + aiPlanGetName(planID) + ": enemy Titan in the field.");
		return true;
	}
	if (samplePop > 0)
	{
		int lostPop = samplePop - ourPop;
		int lostPercent = (lostPop * 100) / samplePop;
		if (lostPercent >= cGodRetreatLossPercent)
		{
			aiEcho("[GodBot] Retreating " + aiPlanGetName(planID) + ": lost " + lostPop + " of " + samplePop + " pop.");
			return true;
		}
	}
	// A cavalry raid is fast enough to leave, so it is not called off by an enemy
	// count at all: it keeps going while the enemy is still this far off, and comes
	// home once they close in.
	if (planID == gGodRaidPlanID && gGodRaidIsCavalry == true)
	{
		int closingIn = godEnemyMilitaryNear(planLoc, cGodCavRaidRetreatRadius);
		if (closingIn > 0)
		{
			aiEcho("[GodBot] Retreating " + aiPlanGetName(planID) + ": " + closingIn + " enemies closed in.");
			return true;
		}
		return false;
	}
	// Judge a raid on the troops on its target, not on the base's whole garrison.
	float checkRadius = 60.0;
	if (planID == gGodRaidPlanID)
	{
		checkRadius = cGodRaidAbortRadius;
	}
	int enemyCount = godEnemyMilitaryNear(planLoc, checkRadius);
	int enemyRatio = (enemyCount * 100) / ourCount;
	if (enemyCount >= 3 && enemyRatio > cGodRetreatEnemyRatioPercent)
	{
		aiEcho("[GodBot] Retreating " + aiPlanGetName(planID) + ": " + enemyCount + " enemies vs our " + ourCount + ".");
		return true;
	}
	return false;
}

void godRetreatPlan(int planID = -1)
{
	aiPlanSetState(planID, cPlanStateDone);
	// Don't immediately walk the main army back out; regroup first. A failed raid
	// of either kind shouldn't hold up the main attack, and a cavalry raid runs on
	// its own clock.
	if (planID != gGodRaidPlanID)
	{
		// Regroup on the rhythm the bot is actually on: the fast interval while
		// pushing, the full slow one otherwise. Setting it here keeps the wait
		// deliberate rather than whatever the last cadence write left behind.
		gAttackManager.mLastAttackTime = xsGetTime();
		gAttackManager.mAttackInterval = godCadenceInterval();
	}
}

//==============================================================================
// Strategy policy
//==============================================================================

// A Conqueror booms: ask for a large villager count to fund a slow push.
void godApplyEconomy()
{
	gOverrideMaxVillagerPop = cGodMaxVillagerPop;
}

void godSetMinorGods(int classical = -1, int heroic = -1, int mythic = -1)
{
	gOverrideClassicalMinorGod = classical;
	gOverrideHeroicMinorGod = heroic;
	gOverrideMythicMinorGod = mythic;
}

// Per major god, pick the minor gods that best suit an economy-first,
// defence-minded, slow-push style. The engine ignores an override it cannot
// obtain, so keying on the major god guarantees the pick is valid. The
// reasoning behind each pick (and the god matchups) is in
// docs/god-bot-minor-gods.md.
void godApplyMinorGods()
{
	switch (cMyCiv)
	{
		// Greeks.
		case cCivZeus:
		{
			godSetMinorGods(cTechClassicalAgeAthena, cTechHeroicAgeApollo, cTechMythicAgeHephaestus);
			break;
		}
		case cCivPoseidon:
		{
			godSetMinorGods(cTechClassicalAgeAres, cTechHeroicAgeAphrodite, cTechMythicAgeHephaestus);
			break;
		}
		case cCivHades:
		{
			godSetMinorGods(cTechClassicalAgeAthena, cTechHeroicAgeAphrodite, cTechMythicAgeHephaestus);
			break;
		}
		case cCivDemeter:
		{
			godSetMinorGods(cTechClassicalAgePan, cTechHeroicAgeHestia, cTechMythicAgeHera);
			break;
		}
		// Egyptians.
		case cCivRa:
		{
			godSetMinorGods(cTechClassicalAgeBast, cTechHeroicAgeSekhmet, cTechMythicAgeHorus);
			break;
		}
		case cCivIsis:
		{
			godSetMinorGods(cTechClassicalAgeBast, cTechHeroicAgeNephthys, cTechMythicAgeThoth);
			break;
		}
		case cCivSet:
		{
			godSetMinorGods(cTechClassicalAgePtah, cTechHeroicAgeSekhmet, cTechMythicAgeHorus);
			break;
		}
		// Norse.
		case cCivThor:
		{
			godSetMinorGods(cTechClassicalAgeForseti, cTechHeroicAgeSkadi, cTechMythicAgeTyr);
			break;
		}
		case cCivOdin:
		{
			godSetMinorGods(cTechClassicalAgeHeimdall, cTechHeroicAgeSkadi, cTechMythicAgeTyr);
			break;
		}
		case cCivLoki:
		{
			godSetMinorGods(cTechClassicalAgeHeimdall, cTechHeroicAgeBragi, cTechMythicAgeTyr);
			break;
		}
		case cCivFreyr:
		{
			godSetMinorGods(cTechClassicalAgeUllr, cTechHeroicAgeAegir, cTechMythicAgeVidar);
			break;
		}
		// Atlanteans.
		case cCivKronos:
		{
			godSetMinorGods(cTechClassicalAgePrometheus, cTechHeroicAgeRheia, cTechMythicAgeAtlas);
			break;
		}
		case cCivOranos:
		{
			godSetMinorGods(cTechClassicalAgeOceanus, cTechHeroicAgeHyperion, cTechMythicAgeHekate);
			break;
		}
		case cCivGaia:
		{
			godSetMinorGods(cTechClassicalAgeOceanus, cTechHeroicAgeRheia, cTechMythicAgeAtlas);
			break;
		}
		// Chinese.
		case cCivFuxi:
		{
			godSetMinorGods(cTechClassicalAgeXuannu, cTechHeroicAgeNuba, cTechMythicAgeHuangdi);
			break;
		}
		case cCivNuwa:
		{
			godSetMinorGods(cTechClassicalAgeHoutu, cTechHeroicAgeRushou, cTechMythicAgeZhurong);
			break;
		}
		case cCivShennong:
		{
			godSetMinorGods(cTechClassicalAgeHoutu, cTechHeroicAgeRushou, cTechMythicAgeHuangdi);
			break;
		}
		// Japanese.
		case cCivAmaterasu:
		{
			godSetMinorGods(cTechClassicalAgeAmeNoUzume, cTechHeroicAgeHachiman, cTechMythicAgeTakemikazuchi);
			break;
		}
		case cCivTsukuyomi:
		{
			godSetMinorGods(cTechClassicalAgeAmeNoUzume, cTechHeroicAgeHachiman, cTechMythicAgeOkuninushi);
			break;
		}
		case cCivSusanoo:
		{
			godSetMinorGods(cTechClassicalAgeMinakatatomi, cTechHeroicAgeRaijin, cTechMythicAgeTakemikazuchi);
			break;
		}
		// Aztecs.
		case cCivHuitzilopochtli:
		{
			godSetMinorGods(cTechClassicalAgePatecatl, cTechHeroicAgeCoatlicue, cTechMythicAgeTlaloc);
			break;
		}
		case cCivTezcatlipoca:
		{
			godSetMinorGods(cTechClassicalAgeHuehuecoyotl, cTechHeroicAgeCoyolxauhqui, cTechMythicAgeXolotl);
			break;
		}
		case cCivQuetzalcoatl:
		{
			godSetMinorGods(cTechClassicalAgePatecatl, cTechHeroicAgeCoatlicue, cTechMythicAgeTlaloc);
			break;
		}
	}
	aiEcho("[GodBot] Minor gods: " + kbTechGetName(gOverrideClassicalMinorGod) + " / "
		+ kbTechGetName(gOverrideHeroicMinorGod) + " / " + kbTechGetName(gOverrideMythicMinorGod) + ".");
}

// No navy unless the map is really naval; otherwise shut naval military down.
// Applied at init and again on every age change, because the engine re-enables its
// default strategy flags as the game goes on.
void godApplyNavalPolicy(ref StrategyData data)
{
	gGodNavalMap = godIsNavalMap();
	if (gGodNavalMap == true)
	{
		aiEcho("[GodBot] Naval map detected - keeping a navy.");
		return;
	}
	aiEcho("[GodBot] Not a naval map - disabling naval military.");
	data.setFlag(cStrategyFlagAutoTrainNavalMilitaryUnits, false);
	data.setFlag(cStrategyFlagCanNavalAttack, false);
	data.setFlag(cStrategyFlagCanNavalDefend, false);
	data.setFlag(cStrategyFlagAutomaticNavalScouting, false);
	data.setFlag(cStrategyFlagMaintainNavalTransport, false);
	gOverrideNavalMaxMilitaryPop = 0;
}

// Publish the current rhythm to the engine. The bot owns the timing through the
// attack gate, so this is what the gate and the next attack both read.
void godApplyAttackCadence()
{
	int interval = godCadenceInterval();
	gAttackManager.mBaseAttackInterval = interval;
	gAttackManager.mAttackInterval = interval;
	gNavalAttackManager.mBaseAttackInterval = interval;
	gNavalAttackManager.mAttackInterval = interval;
	aiEcho("[GodBot] Attack interval set to " + interval + " seconds.");
}

// The engine's attackManager decides *what* to attack, but not *when*: it
// randomises the interval on every launch, and on Hard and above it skips the
// interval altogether once the army is large or the resources are in excess. The
// personality the mod generates is not on the engine's "attack less frequently"
// list, so the slow rhythm we set would be ignored in exactly the late game we
// care about. We hold the gate ourselves and open it only once our own interval
// has elapsed; the engine then launches whenever it is otherwise ready.
bool godAttackGateOpen()
{
	return gAttackManager.waitedLongEnough();
}

// Are we clearly ahead enough to commit to a decisive push? Conservative on
// purpose: we only stop being patient once the game is effectively won.
bool godShouldPush()
{
	// Fortifying is a decision to hold, not to push: committing the army while two
	// or three players are on our bases is what loses it in the open.
	if (gGodStance != cGodStanceNormal)
	{
		return false;
	}
	// A brief poke at the base must not call off a push we already committed to;
	// a real collapse shows up as the army falling below the bar, further down.
	if (godUnderAttack() == true && gGodPushing == false)
	{
		return false;
	}
	int age = kbPlayerGetAge(cMyID);
	if (age < cAge3)
	{
		return false; // Don't commit before Heroic.
	}
	if (aiGetCurrentMilitaryPop() < cGodPushArmyPop)
	{
		return false;
	}
	int target = aiGetMostHatedPlayerID();
	if (target == -1)
	{
		return false;
	}
	// We are an age ahead and have a real army.
	if (age > kbPlayerGetAge(target))
	{
		return true;
	}
	// The bot reads the enemy army directly, so it can tell when it outguns it
	// rather than waiting for a base count to prove it. Once committed, only a
	// real collapse calls it off, so the cadence cannot flip on a wobble.
	int requiredPercent = cGodPushHoldPercent;
	if (gGodPushing == false)
	{
		requiredPercent = cGodPushAdvantagePercent;
	}
	float ourPower = godArmyPower(cMyID);
	float enemyPower = godArmyPower(target);
	// No enemy army left to stop us.
	if (enemyPower <= 0.0)
	{
		return true;
	}
	float required = (enemyPower * requiredPercent) / 100.0;
	return ourPower >= required;
}

// Pause the engine's Titan Gate placement while we're being pushed. Its state
// machine lives in file-scoped globals inside godpowers.xs, so the rule itself is
// the only handle we have: disabling it suspends placement, and re-enabling
// resumes it from wherever it stopped.
void godHoldTitanGate()
{
	if (xsIsRuleEnabled("titanGateConstructionMonitor") == false)
	{
		return;
	}
	aiEcho("[GodBot] Under attack - postponing the Titan Gate.");
	xsDisableRule("titanGateConstructionMonitor");
	gGodHeldTitanGate = true;
}

void godReleaseTitanGate()
{
	if (gGodHeldTitanGate == false)
	{
		return;
	}
	gGodHeldTitanGate = false;
	if (kbGodPowerGetCost(cProtoPowerTitanGate, cMyID) != 0.0)
	{
		return;
	}
	xsEnableRule("titanGateConstructionMonitor");
	xsRuleIgnoreIntervalOnce("titanGateConstructionMonitor");
}

// Latch the stalemate once we have sat in Mythic long enough with the enemy there
// too. An age lead is a win in progress, and the push is the answer to that.
void godUpdateStalemate()
{
	if (gGodStalemate == true)
	{
		return;
	}
	if (kbPlayerGetAge(cMyID) < cAge4)
	{
		return;
	}
	if (gGodMythicSince == -1)
	{
		gGodMythicSince = xsGetTime();
	}
	int target = aiGetMostHatedPlayerID();
	if (target == -1 || kbPlayerGetAge(target) < cAge4)
	{
		return;
	}
	int inMythic = xsGetTime() - gGodMythicSince;
	if (inMythic < cGodStalemateSeconds)
	{
		return;
	}
	gGodStalemate = true;
	aiEcho("[GodBot] Stalemate after " + inMythic + "s in Mythic - going for a Titan.");
}

// Can the bank pay for this tech with the reserve on top? The army keeps the rest.
bool godBankCovers(int techID = -1)
{
	float[] cost = kbTechGetCost(techID);
	for (int i = 0; i < cNumberResources; i++)
	{
		float needed = (cost[i] * (100 + cGodTitanReservePercent)) / 100.0;
		if (kbResourceGet(i) < needed)
		{
			return false;
		}
	}
	// Favour is billed on its own; the engine checks it separately for the same tech.
	float neededFavor = kbTechGetCostPerResource(techID, cResourceFavor);
	return kbResourceGet(cResourceFavor) >= neededFavor;
}

// The engine researches Secrets of the Titans only on a surplus its needs
// bookkeeping reports long after the bank is full, which is why a Titan can arrive
// with tens of thousands banked and nothing else to spend on. Once we are
// stalemated, buy the tech ourselves: a tech uses no builders and no army, so it
// costs nothing but spare resources, and the engine builds the Gate from there.
void godResearchTitanTech()
{
	if (gGodStalemate == false || gGodTitanReached == true)
	{
		return;
	}
	if (godUnderAttack() == true)
	{
		return;
	}
	if (kbGodPowerGetNumCharges(cProtoPowerTitanGate, cMyID) >= 1)
	{
		return; // The Gate is already ours to place.
	}
	if (kbTechGetStatus(cTechSecretsOfTheTitans) != cTechStatusObtainable)
	{
		return;
	}
	if (aiPlanGetIDByTypeAndVariableIntValue(cPlanResearch, cResearchPlanTechID, cTechSecretsOfTheTitans) != -1)
	{
		return;
	}
	if (godBankCovers(cTechSecretsOfTheTitans) == false)
	{
		return;
	}
	aiEcho("[GodBot] Researching Secrets of the Titans: food=" + xsFloatToInt(kbResourceGet(cResourceFood))
		+ " wood=" + xsFloatToInt(kbResourceGet(cResourceWood))
		+ " gold=" + xsFloatToInt(kbResourceGet(cResourceGold))
		+ " favor=" + xsFloatToInt(kbResourceGet(cResourceFavor)) + ".");
	researchSimpleTech(cTechSecretsOfTheTitans, -1, -1, 99);
}

// The Titan breaks a stalemate, so it is not worth paying for before one. The
// Wonder comes after the first Titan and only adds more of them. Being pushed
// cancels a Wonder in progress and postpones the Gate.
void godManageWonderAndTitanGate(ref StrategyData data)
{
	if (gGodTitanReached == false && kbUnitCount(cUnitTypeAbstractTitan, cMyID, cUnitStateAlive) >= 1)
	{
		gGodTitanReached = true;
		aiEcho("[GodBot] First Titan is out - the Wonder is allowed now.");
	}
	// Fortifying counts as being under pressure: a Wonder or a Titan Gate is a long
	// investment that would be lost while several players are on our bases.
	bool attacked = godUnderAttack() == true || gGodStance == cGodStanceFortify;
	data.setFlag(cStrategyFlagBuildTitan, gGodStalemate == true && attacked == false);
	data.setFlag(cStrategyFlagBuildWonder, gGodTitanReached == true && attacked == false);
	if (attacked == true)
	{
		godCancelBuildPlans(cUnitTypeWonder);
		godHoldTitanGate();
		return;
	}
	godReleaseTitanGate();
}

// Feeding an army to a Titan just loses the army. While one is on the field and we
// cannot answer it — no Titan of our own, no army big enough to kill it — hold the
// army at home, where the towers and our own gate are, and stop raiding into it.
bool godTitanAllowsAttack()
{
	if (godEnemyTitanID() == -1)
	{
		return true;
	}
	return kbUnitCount(cUnitTypeAbstractTitan, cMyID, cUnitStateAlive) >= 1
		|| aiGetCurrentMilitaryPop() >= cGodTitanHuntArmyPop;
}

// Choose the stance for this second. A 1v1 never leaves "normal". A team game
// fortifies once enough enemies are on our bases, stays fortified through a quiet
// spell so the stance cannot flicker, and otherwise helps an ally in trouble.
int godPickStance()
{
	if (gGodTeamGame == false)
	{
		return cGodStanceNormal;
	}
	bool pressed = gGodThreatPlayers >= cGodFortifyEnemyPlayers;
	if (gGodThreatPower >= cGodThreatMinPower
		&& (gGodThreatPower * 100.0) > (gGodHomePower * cGodFortifyThreatPercent))
	{
		pressed = true;
	}
	if (pressed == true)
	{
		gGodLastThreatTime = xsGetTime();
		return cGodStanceFortify;
	}
	if (gGodStance == cGodStanceFortify && gGodLastThreatTime != -1
		&& (xsGetTime() - gGodLastThreatTime) < cGodFortifyQuietSeconds)
	{
		return cGodStanceFortify;
	}
	return cGodStanceNormal;
}

// Publish the stance to the engine. Fortifying raises the number of towers the
// engine's towerManager keeps per base; normal hands the number back to the engine.
void godApplyStance(ref StrategyData data)
{
	if (gGodStance == cGodStanceFortify)
	{
		data.mTowerAmountPerTCBase = cGodFortifyTowersPerBase;
		return;
	}
	data.mTowerAmountPerTCBase = cCalculateNumberTowersAutomatically;
}

// How defensible a base is: its towers, its Town Center, any Fortress, and the
// houses packed around it. Fighting under these is worth giving up ground for, so
// the fallback picks the base with the most of them.
float godBaseDefenceScore(int baseID = -1)
{
	float score = 0.0;
	score = score + getCountOfOwnAliveBuildingInBase(cUnitTypeAbstractTower, baseID) * cGodScoreTower;
	score = score + getCountOfOwnAliveBuildingInBase(cUnitTypeAbstractSocketedTownCenter, baseID) * cGodScoreTownCenter;
	score = score + getCountOfOwnAliveBuildingInBase(cUnitTypeAbstractFortress, baseID) * cGodScoreFortress;
	score = score + getCountOfOwnAliveBuildingInBase(cUnitTypeHouse, baseID) * cGodScoreHouse;
	return score;
}

// Our Town Center base with the strongest defences.
int godStrongestBase()
{
	int bestBase = -1;
	float bestScore = -1.0;
	int numBases = kbBaseGetNumber(cMyID);
	for (int i = 0; i < numBases; i++)
	{
		int baseID = kbBaseGetIDByIndex(cMyID, i);
		if (kbBaseIsFlagSet(cMyID, baseID, cBaseFlagTownCenter) == false)
		{
			continue;
		}
		float score = godBaseDefenceScore(baseID);
		if (score > bestScore)
		{
			bestScore = score;
			bestBase = baseID;
		}
	}
	return bestBase;
}

//==============================================================================
// Strategy
//==============================================================================
Strategy godBotStrategy()
{
	Strategy strategy;
	strategy.mID = cStrategySPCCustom;
	strategy.mAge = cAge1;
	strategy.mName = "GodBot";

	strategy.mInitFunc = [](ref StrategyData data) -> bool
	{
		aiEcho("=== [GodBot] strategy init ===");
		godCountPlayers();
		aiEcho("[GodBot] Game shape: " + gGodEnemyCount + " enemies, " + gGodAllyCount + " allies.");
		data.enableAllStrategyFlags();
		godApplyNavalPolicy(data);
		godApplyAttackCadence();
		gGodLastAge = kbPlayerGetAge(cMyID);
		return true;
	};

	// Runs every second. Returning false would end the strategy, so always true.
	strategy.mUpdateFunc = [](ref StrategyData data) -> bool
	{
		godUpdateThreat();
		int age = kbPlayerGetAge(cMyID);
		if (age != gGodLastAge)
		{
			gGodLastAge = age;
			godApplyAttackCadence();
			// The engine re-enables its default strategy flags as the game goes on, so
			// the naval shutdown has to be re-applied at each age, not just at init.
			godApplyNavalPolicy(data);
		}
		int stance = godPickStance();
		if (stance != gGodStance)
		{
			string from = godStanceName(gGodStance);
			gGodStance = stance;
			aiEcho("[GodBot] Stance: " + from + " -> " + godStanceName(stance)
				+ " (threatPlayers=" + gGodThreatPlayers + ", threat=" + xsFloatToInt(gGodThreatPower)
				+ ", home=" + xsFloatToInt(gGodHomePower) + ").");
			godApplyStance(data);
			godApplyAttackCadence();
			if (stance == cGodStanceFortify)
			{
				// towerManager only re-checks every couple of minutes; nudge it so the
				// extra towers start as soon as we fortify rather than ages later.
				xsRuleIgnoreIntervalOnce("towerManager");
			}
		}
		bool pushing = godShouldPush();
		if (pushing != gGodPushing)
		{
			gGodPushing = pushing;
			if (pushing == true)
			{
				aiEcho("[GodBot] Committed to a decisive push.");
			}
			else
			{
				aiEcho("[GodBot] Back to the slow rhythm.");
			}
			godApplyAttackCadence();
		}
		godUpdateStalemate();
		godResearchTitanTech();
		godManageWonderAndTitanGate(data);
		// cStrategyFlagCanAttack is the engine's gate on its attackManager, so
		// holding it here is what makes the cadence ours rather than the engine's.
		// A team game only attacks from the normal stance; fortifying holds the army
		// home with the towers instead. A fallback in progress holds it too, so the
		// engine cannot walk the army back out while it is regrouping.
		data.setFlag(cStrategyFlagCanAttack,
			gGodStance == cGodStanceNormal && aiPlanGetIsIDValid(gGodFallbackPlanID) == false
			&& godTitanAllowsAttack() && godAttackGateOpen());
		return true;
	};

	return strategy;
}

void godBotStrategySetup()
{
	Strategy strategy = godBotStrategy();
	gStrategyManager.addStrategy(strategy);
}

//==============================================================================
// Monitors
//==============================================================================

// Scrap any warships that slip through when the map isn't a naval one.
rule godNavalCleanupMonitor
inactive
minInterval 30
{
	if (gGodNavalMap == true)
	{
		return;
	}
	int[] warships = new int(0, -1);
	int queryID = kbUnitQueryCreate("GodBot warships");
	kbUnitQuerySetPlayerID(queryID, cMyID, false);
	kbUnitQuerySetUnitType(queryID, cUnitTypeLogicalTypeNavalMilitary);
	kbUnitQuerySetState(queryID, cUnitStateAlive);
	int num = kbUnitQueryExecute(queryID);
	for (int i = 0; i < num; i++)
	{
		int unitID = kbUnitQueryGetResult(queryID, i);
		// The query can hand back a unit that died since the KB was built;
		// aiTaskDeleteUnits warns about those, so drop them here.
		if (kbUnitGetIsIDValid(unitID) == true)
		{
			warships.add(unitID);
		}
	}
	// The engine keeps a named query until it is destroyed; leaking one per run
	// makes every later kbUnitQueryCreate warn that the name is taken.
	kbUnitQueryDestroy(queryID);
	if (warships.size() > 0)
	{
		// Name what leaked: on a map with water something still queues a warship
		// even with every naval flag cleared, and the log is the only way to find it.
		string leaked = "";
		for (int i = 0; i < warships.size(); i++)
		{
			leaked = leaked + " " + kbProtoUnitGetName(kbUnitGetProtoUnitID(warships[i]))
				+ "#" + warships[i] + " at " + kbUnitGetPosition(warships[i]) + ";";
		}
		aiEcho("[GodBot] Not a naval map - scrapping " + warships.size() + " warship(s):" + leaked);
		aiTaskDeleteUnits(warships);
	}
}

// Every village (TC base) gets one Temple and one military building.
rule godVillageMonitor
inactive
minInterval 20
{
	if (checkStrategyFlag(cStrategyFlagAutoBuildMilitaryBuildings) == false)
	{
		return;
	}
	int numBases = kbBaseGetNumber(cMyID);
	for (int i = 0; i < numBases; i++)
	{
		int baseID = kbBaseGetIDByIndex(cMyID, i);
		if (kbBaseIsFlagSet(cMyID, baseID, cBaseFlagTownCenter) == false)
		{
			continue;
		}
		if (getCountOfOwnAliveBuildingInBase(cUnitTypeTemple, baseID) == 0 &&
			getAmountBuildPlansInBase(cUnitTypeTemple, baseID) == 0)
		{
			createSimpleBuildPlan(cUnitTypeTemple, 1, 55, gMilitaryBuildingsCategoryID, baseID);
			continue;
		}
		if (godBaseHasMilitaryBuilding(baseID) == false)
		{
			int puid = godPickMilitaryBuilding();
			if (puid != -1)
			{
				createSimpleBuildPlan(puid, 1, 45, gMilitaryBuildingsCategoryID, baseID);
			}
		}
	}
}

// Turrets upgraded as early as possible: research the next tower upgrade the
// moment it is obtainable. We publish the plan through the engine's own
// gTowerOffensiveResearchPlanID so the stock tower monitor defers to us.
rule godTowerUpgradeMonitor
inactive
minInterval 10
{
	if (cGameModeCurrent == cGameModeDeathmatch)
	{
		xsDisableRule("godTowerUpgradeMonitor");
		return;
	}
	if (cDifficultyCurrent == cDifficultyEasy)
	{
		xsDisableRule("godTowerUpgradeMonitor");
		return;
	}
	if (checkStrategyFlag(cStrategyFlagAutoResearchMilitaryUpgrades) == false)
	{
		return;
	}
	if (aiPlanGetIsIDValid(gTowerOffensiveResearchPlanID) == true)
	{
		return;
	}
	if (kbUnitCount(cUnitTypeSentryTower, cMyID, cUnitStateAlive) < 1)
	{
		return;
	}
	if (areAtMaxConcurrentResearchPlans("godTowerUpgradeMonitor") == true)
	{
		return;
	}
	int tech = godNextTowerUpgrade();
	if (tech == -1)
	{
		return;
	}
	aiEcho("[GodBot] Researching tower upgrade: " + kbTechGetName(tech) + ".");
	gTowerOffensiveResearchPlanID = researchSimpleTech(tech, cUnitTypeSentryTower, -1, 70);
	aiPlanSetEventHandler(gTowerOffensiveResearchPlanID, cPlanEventStateChange, "resetOffensiveTowerResearchPlan");
}

// Pull back each attack that is bleeding out, outnumbered on the spot, or standing
// in front of a Titan. Every attack is judged on its own, so a failing raid never
// recalls the main army. Retreating is defensive, so this keeps running while
// godTitanAllowsAttack holds attacks back: an army already in the field still
// comes home.
rule godRetreatMonitor
inactive
minInterval 10
{
	int now = xsGetTime();
	int[] plans = aiPlanGetIDsByType(cPlanAttack);
	for (int i = 0; i < plans.size(); i++)
	{
		int planID = plans[i];
		if (aiPlanGetParentID(planID) != -1)
		{
			continue;
		}
		// The engine tags its Titan plans. A Titan is one unit, so the outnumbered
		// check below would recall it on every pass and it would never land.
		if (aiPlanGetUserVariableIndex(planID, "Titan Plan") != -1)
		{
			continue;
		}
		int state = aiPlanGetState(planID);
		if (state != cPlanStateGoto && state != cPlanStateAttack)
		{
			continue;
		}
		int[] units = aiPlanGetUnits(planID);
		if (units.size() == 0)
		{
			continue;
		}
		int ourPop = kbUnitsGetPower(units, true);
		// Keep the sample until its window has passed, so losses add up across checks.
		int samplePop = aiPlanGetVariableInt(planID, cGodRetreatSamplePopVar, 0);
		int sampleAge = now - aiPlanGetVariableInt(planID, cGodRetreatSampleTimeVar, 0);
		if (samplePop == -1 || sampleAge > cGodRetreatLossWindow)
		{
			samplePop = ourPop;
			aiPlanSetVariableInt(planID, cGodRetreatSamplePopVar, 0, ourPop);
			aiPlanSetVariableInt(planID, cGodRetreatSampleTimeVar, 0, now);
		}
		if (godAttackIsLosing(planID, units.size(), ourPop, samplePop) == true)
		{
			godRetreatPlan(planID);
		}
	}
}

// While the army at a base is losing, take it back to the base with the most
// defences instead of letting it die in the open. Fighting under towers and houses
// is worth giving up ground for. Runs in every stance: a 1v1 army losing a fight in
// the open should fall back too, not only a team game.
rule godFallbackMonitor
inactive
minInterval 5
{
	if (aiPlanGetIsIDValid(gGodFallbackPlanID) == true)
	{
		bool release = false;
		if (xsGetTime() - gGodFallbackSince >= cGodFallbackHoldSeconds)
		{
			release = true;
		}
		if (kbBaseGetIsIDValid(cMyID, gGodFallbackFromBaseID) == false)
		{
			release = true;
		}
		else
		{
			vector holdLoc = kbBaseGetLocation(cMyID, gGodFallbackFromBaseID);
			float holdRadius = godBaseThreatRadius(gGodFallbackFromBaseID);
			float enemy = godPowerNear(cPlayerRelationEnemyNotGaia, holdLoc, holdRadius);
			float ours = godPowerNear(cMyID, holdLoc, holdRadius);
			if ((enemy * 100.0) <= (ours * cGodFallbackReleasePercent))
			{
				release = true;
			}
		}
		if (release == true)
		{
			aiEcho("[GodBot] Fallback over - the army returns to the engine's defence.");
			aiPlanDestroy(gGodFallbackPlanID);
			gGodFallbackPlanID = -1;
			gGodFallbackFromBaseID = -1;
			gGodFallbackSince = -1;
		}
		return;
	}
	int base = gGodThreatBaseID;
	if (base == -1)
	{
		return;
	}
	vector loc = kbBaseGetLocation(cMyID, base);
	float radius = godBaseThreatRadius(base);
	float enemy = godPowerNear(cPlayerRelationEnemyNotGaia, loc, radius);
	float ours = godPowerNear(cMyID, loc, radius);
	if (enemy < cGodThreatMinPower || (enemy * 100.0) <= (ours * cGodFallbackRatioPercent))
	{
		return;
	}
	int target = godStrongestBase();
	if (target == -1 || target == base)
	{
		// Already fighting under our best defences, so there is nowhere better to go.
		return;
	}
	// Recall any attack that is still walking out, then park the army on the strong
	// base. The plan outranks the engine's primary defend plan so the units move.
	retreatArmies(kbBaseGetLocation(cMyID, target));
	gGodFallbackPlanID = createDefendPlanForPoint("GodBot Fallback", kbBaseGetLocation(cMyID, target), cGodFallbackPriority);
	if (gGodFallbackPlanID == -1)
	{
		return;
	}
	aiPlanAddUnitType(gGodFallbackPlanID, cUnitTypeLogicalTypeLandMilitary, 0, 0, 200);
	aiPlanSetFlag(gGodFallbackPlanID, cPlanFlagCantBeStolenFrom, true);
	aiPlanSetVariableFloat(gGodFallbackPlanID, cDefendPlanEngageRange, 0, godBaseThreatRadius(target));
	gGodFallbackSince = xsGetTime();
	gGodFallbackFromBaseID = base;
	aiEcho("[GodBot] Falling back from " + kbBaseGetNameByID(cMyID, base) + " to "
		+ kbBaseGetNameByID(cMyID, target) + ": enemy " + xsFloatToInt(enemy)
		+ " vs our " + xsFloatToInt(ours) + ".");
}

// When we can't commit to a full attack, send a small group to hit the enemy
// economy instead (drop sites first, then villagers).
rule godRaidMonitor
inactive
minInterval 90
{
	// Fortifying means the army stays home; the raid parties were dying to the
	// enemy's shared army in a team game anyway. A fallback in progress holds the
	// army at the strong base, so nothing splits off to raid either.
	if (gGodStance != cGodStanceNormal || aiPlanGetIsIDValid(gGodFallbackPlanID) == true)
	{
		return;
	}
	// The strategy flag is the engine's attackManager gate, held closed between our
	// own attacks; a raid reads our willingness to fight instead.
	if (godTitanAllowsAttack() == false)
	{
		return;
	}
	if (godUnderAttack() == true)
	{
		return;
	}
	if (gGodPushing == true)
	{
		return; // Don't split the army while committing.
	}
	if (godRaidInField() == true)
	{
		return; // One raid at a time.
	}
	int target = aiGetMostHatedPlayerID();
	if (target == -1)
	{
		return;
	}
	// Only raid with spare army; otherwise stay massed for the main attack.
	int[] homeUnits = aiPlanGetUnits(gPrimaryLandDefendPlan);
	if (kbUnitsGetPower(homeUnits, true) < 10)
	{
		return;
	}
	int raidTargetID = godFindRaidTarget(target);
	if (raidTargetID == -1)
	{
		return;
	}
	vector raidPoint = kbUnitGetPosition(raidTargetID);
	godLaunchRaid("GodBot Raid", raidPoint, cUnitTypeLogicalTypeLandMilitary, 4, 8, 20, false);
	aiEcho("[GodBot] Raiding enemy economy at " + raidPoint + ".");
}

// A fast raid on the enemy's gold. Cavalry rides in, kills the miners, and leaves
// before the army can answer, so this one is allowed while the main army is pushing
// — that is exactly when the enemy's army is away from its mines.
rule godCavRaidMonitor
inactive
minInterval 60
{
	// Fortifying means the army stays home; the raid parties were dying to the
	// enemy's shared army in a team game anyway. A fallback in progress holds the
	// army at the strong base, so nothing splits off to raid either.
	if (gGodStance != cGodStanceNormal || aiPlanGetIsIDValid(gGodFallbackPlanID) == true)
	{
		return;
	}
	// The strategy flag is the engine's attackManager gate, held closed between our
	// own attacks; a raid reads our willingness to fight instead.
	if (godTitanAllowsAttack() == false)
	{
		return;
	}
	if (godUnderAttack() == true)
	{
		return;
	}
	if (godRaidInField() == true)
	{
		return; // One raid at a time.
	}
	if (kbUnitCount(cUnitTypeAbstractCavalry, cMyID, cUnitStateAlive) < cGodCavRaidMinCavalry)
	{
		return; // No cavalry in this army; the foot raid is all we have.
	}
	int raidTargetID = godFindGoldMineTarget();
	if (raidTargetID == -1)
	{
		return; // Nobody is mining, nothing to hit.
	}
	vector raidPoint = kbUnitGetPosition(raidTargetID);
	godLaunchRaid("GodBot Cavalry Raid", raidPoint, cUnitTypeAbstractCavalry, 3, 6, 15, true);
	aiEcho("[GodBot] Cavalry raiding the enemy gold at " + raidPoint + ".");
}

// One structured line every 30s for offline analysis. Read it back from
// temp/Logs/MythRetoldAIOutputPlayer<N>.txt; see AGENTS.md.
rule godTelemetryMonitor
inactive
minInterval 30
{
	int target = aiGetMostHatedPlayerID();
	int enemyAge = -1;
	if (target != -1)
	{
		enemyAge = kbPlayerGetAge(target);
	}
	int enemyTitan = 0;
	if (godEnemyTitanID() != -1)
	{
		enemyTitan = 1;
	}
	string state = "hold";
	if (gGodPushing == true)
	{
		state = "push";
	}
	// Reported on its own line: the stance stays "push" while the army is in the
	// field, so folding the two together would hide a base being hit during a push.
	int underAttack = 0;
	if (godUnderAttack() == true)
	{
		underAttack = 1;
	}
	int fallback = 0;
	if (aiPlanGetIsIDValid(gGodFallbackPlanID) == true)
	{
		fallback = 1;
	}
	aiEcho("[GBOT] t=" + xsGetTime()
		+ " age=" + kbPlayerGetAge(cMyID)
		+ " vills=" + kbUnitCount(cUnitTypeAbstractVillager, cMyID, cUnitStateAlive)
		+ " pop=" + kbPlayerGetPop(cMyID) + "/" + kbPlayerGetPopCap(cMyID)
		+ " army=" + aiGetCurrentMilitaryPop()
		+ " food=" + xsFloatToInt(kbResourceGet(cResourceFood))
		+ " wood=" + xsFloatToInt(kbResourceGet(cResourceWood))
		+ " gold=" + xsFloatToInt(kbResourceGet(cResourceGold))
		+ " enemyAge=" + enemyAge
		+ " enemyTitan=" + enemyTitan
		+ " titans=" + kbUnitCount(cUnitTypeAbstractTitan, cMyID, cUnitStateAlive)
		+ " wonder=" + kbUnitCount(cUnitTypeWonder, cMyID, cUnitStateAlive)
		+ " state=" + state
		+ " underAttack=" + underAttack
		+ " enemies=" + gGodEnemyCount
		+ " allies=" + gGodAllyCount
		+ " stance=" + godStanceName(gGodStance)
		+ " threat=" + xsFloatToInt(gGodThreatPower)
		+ " threatPlayers=" + gGodThreatPlayers
		+ " fallback=" + fallback);
}

// Player counts change as players are eliminated, so refresh them on a timer rather
// than only at init.
rule godPlayersMonitor
inactive
minInterval 30
{
	godCountPlayers();
}

//==============================================================================
/*	preInit()

	This function is called in main() before any of the normal initialization
	happens. Use it to override default values of variables as needed.
*/
//==============================================================================
void preInit()
{
	aiEcho("=== [GodBot] preInit() - installing Conqueror strategy ===");
	godApplyEconomy();
	godApplyMinorGods();
	setOverrideStrategy(godBotStrategySetup);
}

//==============================================================================
/*	postInit()

	This function is called in main() after the normal initialization is
	complete. Use it to override settings, build orders, or army plans.
*/
//==============================================================================
void postInit()
{
	aiEcho("=== [GodBot] postInit() - activating monitors ===");
	xsEnableRule("godNavalCleanupMonitor");
	xsEnableRule("godPlayersMonitor");
	xsEnableRule("godVillageMonitor");
	xsEnableRule("godTowerUpgradeMonitor");
	xsEnableRule("godRetreatMonitor");
	xsEnableRule("godFallbackMonitor");
	xsEnableRule("godRaidMonitor");
	xsEnableRule("godCavRaidMonitor");
	xsEnableRule("godTelemetryMonitor");
}
