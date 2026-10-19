//==============================================================================
// god_bot.xs - Age of Mythology: Retold God Bot
//
// A win-at-all-costs bot: it plays the Conqueror's slow, economy-heavy game but
// decides with information a human player cannot have. See docs/god-bot-design.md
// for the goal and the powers it exploits.
//
// Four responsibilities:
//   1. Economy   - engine auto-eco, villager cap, minor-god picks.
//   2. Defence   - the engine's defend plan, towers as needed, one ally assist.
//   3. Offence   - the engine's attack manager on a deliberately slow cadence.
//   4. Endgame   - the engine's Titan and Wonder monitors, unlocked on a stalemate.
//
// The land army has one owner: the engine's gPrimaryLandDefendPlan. The only
// custom plan that may claim it is the transient ally assist. See the complexity
// budget in AGENTS.md before adding another.
//==============================================================================
include "core/main.xs";

//==============================================================================
// Tunables
//==============================================================================
// Conqueror already attacks on a slow rhythm; we slow it down further. The engine
// randomises the interval on launch and skips its time check on Hard and above once
// the army is large, so the strategy gate holds the rhythm ourselves.
const float cGodCadenceMultiplier = 1.2;

// Decisive push: once we are clearly ahead, attack on a fast cadence instead.
const int cGodPushArmyPop = 40;
const int cGodPushInterval = 90;
// Committing takes the full margin; staying committed only takes still being ahead,
// so a wobble around the threshold cannot flip the cadence back and forth.
const int cGodPushAdvantagePercent = 150;
const int cGodPushHoldPercent = 110;

// Economy: Conqueror-style boom target for the villager count.
const int cGodMaxVillagerPop = 90;

// Retreat an attack once the enemy on the spot outnumbers it by this ratio.
const int cGodRetreatEnemyRatioPercent = 150;

// The enemy's Titan: call an attack off when it is close, and only commit again
// with an army that can actually take one on.
const float cGodTitanFleeRadius = 45.0;
const int cGodTitanHuntArmyPop = 60;
// A Mythic game that has gone on this long with no age lead is a stalemate, and the
// engine's Titan and Wonder monitors are unlocked.
const int cGodStalemateSeconds = 360;

// A raid is a small group, so a whole base garrison counts as "outnumbered". Judge
// it only on the troops on its target, and refuse a site a small party cannot take.
const float cGodRaidTargetRadius = 30.0;
const float cGodRaidAbortRadius = 25.0;
const int cGodRaidMaxGuard = 2;
const int cGodCavRaidMinCavalry = 4;
const float cGodCavRaidMineRadius = 30.0;
const float cGodCavRaidRetreatRadius = 20.0;

// Defence: the engine reports enemy power per base, so a lone scout does not count.
// Towers are raised while the base is actually overrun, and one is nudged toward the
// approach the enemy is using.
const int cGodThreatMinPower = 5;
const float cGodThreatExtraRadius = 20.0;
const int cGodDefendTowersPerBase = 6;
const float cGodFrontTowerDistance = 20.0;
const int cGodFrontTowerPriority = 55;

// Help an ally whose base is being overrun, but only while our own bases are quiet
// and only a capped share of the army. Losing an ally leaves us facing the enemies
// alone, so keeping one alive is worth the detour.
const float cGodAssistMinEnemyPower = 10.0;
const int cGodAssistRatioPercent = 150;
const int cGodAssistMaxSharePercent = 50;
const int cGodAssistMinUnits = 5;
const float cGodAssistMaxDistance = 200.0;
const int cGodAssistQuietSeconds = 30;
const int cGodAssistPriority = 40;

// A 12-player brawl is not a 2v2: the team behaviour only makes sense with an ally
// and a normal team size.
const int cGodTeamMaxEnemies = 4;

//==============================================================================
// State
//==============================================================================
bool gGodNavalMap = false;
bool gGodPushing = false;
int gGodLastAge = -1;
bool gGodStalemate = false;
int gGodMythicSince = -1;
bool gGodTitanReached = false;

bool gGodDefendHome = false;
int gGodFrontTowerPlanID = -1;

int gGodRaidPlanID = -1;
bool gGodRaidIsCavalry = false;

int gGodEnemyCount = 0;
int gGodAllyCount = 0;
bool gGodTeamGame = false;

int gGodAssistPlanID = -1;
int gGodAssistAllyID = -1;
int gGodAssistBaseID = -1;
int gGodAssistQuietSince = -1;

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
	gGodTeamGame = gGodAllyCount >= 1 && gGodEnemyCount <= cGodTeamMaxEnemies;
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
// and a four-pop hero alike, so the push decision uses the power that decides fights.
float godArmyPower(int playerID = -1)
{
	int queryID = useSimpleUnitQuery(cUnitTypeLogicalTypeLandMilitary, playerID, cUnitStateAlive);
	kbUnitQueryExecute(queryID);
	return kbUnitsGetPower(kbUnitQueryGetResults(queryID));
}

// Combat power of one player's land military around a point.
float godPowerNear(int player = cMyID, vector location = cInvalidVector, float radius = 60.0)
{
	int queryID = useSimpleUnitQuery(cUnitTypeLogicalTypeLandMilitary, player, cUnitStateAlive, location, radius);
	kbUnitQueryExecute(queryID);
	return kbUnitQueryGetPower(queryID);
}

// A base's own radius plus a margin, so troops massing just outside it still count.
float godBaseThreatRadius(int baseID = -1)
{
	return kbBaseGetDistance(cMyID, baseID) + cGodThreatExtraRadius;
}

// Prefer the enemy drop site the enemy can least defend; fall back to any villager.
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

// Enemy villagers working a point.
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

// Is this attack outnumbered on the spot, or standing in front of a Titan?
bool godAttackIsLosing(int planID = -1, int ourCount = 0)
{
	vector planLoc = aiPlanGetLocation(planID);
	if (planLoc == cInvalidVector)
	{
		return false;
	}
	// A Titan kills an army faster than any count shows, so never feed it.
	if (godTitanNear(planLoc) == true)
	{
		aiEcho("[GodBot] Retreating " + aiPlanGetName(planID) + ": enemy Titan in the field.");
		return true;
	}
	// A cavalry raid is fast enough to leave, so it is judged by how close the enemy
	// is rather than by how many of them there are.
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
	// Don't immediately walk the main army back out; regroup for one interval. A
	// failed raid of either kind shouldn't hold up the main attack.
	if (planID != gGodRaidPlanID)
	{
		gAttackManager.mLastAttackTime = xsGetTime();
		gAttackManager.mAttackInterval = godCadenceInterval();
	}
}

// The ally base that most needs help, or -1, with the ally's player id written to
// allyID. Prefers the ally closest to being wiped out (fewest Town Center bases
// left), then the base where the enemy's edge is biggest. Only reads allies while
// our own bases are quiet.
int godAssistTarget(ref int allyID)
{
	allyID = -1;
	if (gGodTeamGame == false || gDefensivelyOverrun == true)
	{
		return -1;
	}
	int bestAlly = -1;
	int bestBase = -1;
	int bestBases = 0;
	float bestGap = 0.0;
	for (int a = 1; a <= cNumberPlayers; a++)
	{
		if (a == cMyID || kbPlayerHasLost(a) == true || kbPlayerIsAlly(a) == false)
		{
			continue;
		}
		int allyBases = 0;
		int candidate = -1;
		float candidateGap = 0.0;
		int numBases = kbBaseGetNumber(a);
		for (int i = 0; i < numBases; i++)
		{
			int baseID = kbBaseGetIDByIndex(a, i);
			if (kbBaseIsFlagSet(a, baseID, cBaseFlagTownCenter) == false)
			{
				continue;
			}
			allyBases++;
			vector loc = kbBaseGetLocation(a, baseID);
			if (xsVectorLength(loc - kbBaseGetLocation(cMyID, kbBaseGetMainID(cMyID))) > cGodAssistMaxDistance)
			{
				continue;
			}
			float radius = kbBaseGetDistance(a, baseID) + cGodThreatExtraRadius;
			float enemy = godPowerNear(cPlayerRelationEnemyNotGaia, loc, radius);
			if (enemy < cGodAssistMinEnemyPower)
			{
				continue;
			}
			float allyPower = godPowerNear(a, loc, radius);
			float gap = enemy - allyPower;
			if ((enemy * 100.0) > (allyPower * cGodAssistRatioPercent) && gap > candidateGap)
			{
				candidate = baseID;
				candidateGap = gap;
			}
		}
		if (candidate == -1)
		{
			continue;
		}
		if (bestBase == -1 || allyBases < bestBases || (allyBases == bestBases && candidateGap > bestGap))
		{
			bestAlly = a;
			bestBase = candidate;
			bestBases = allyBases;
			bestGap = candidateGap;
		}
	}
	allyID = bestAlly;
	return bestBase;
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
// obtain, so keying on the major god guarantees the pick is valid.
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

// Publish the current rhythm to the engine. The strategy gate and the next attack
// both read it.
void godApplyAttackCadence()
{
	int interval = godCadenceInterval();
	gAttackManager.mBaseAttackInterval = interval;
	gAttackManager.mAttackInterval = interval;
	gNavalAttackManager.mBaseAttackInterval = interval;
	gNavalAttackManager.mAttackInterval = interval;
	aiEcho("[GodBot] Attack interval set to " + interval + " seconds.");
}

// The engine's attackManager decides *what* to attack, but not *when*: it randomises
// the interval on launch, and on Hard and above it skips the time check once the army
// is large. Holding cStrategyFlagCanAttack closed until our own interval has elapsed
// makes the rhythm ours. The engine still launches when it is otherwise ready.
bool godAttackGateOpen()
{
	return gAttackManager.waitedLongEnough();
}

// Are we clearly ahead enough to commit to a decisive push? Conservative on purpose:
// the bot only stops being patient once the game is effectively won.
bool godShouldPush()
{
	// Defending home is a decision to hold, not to push: committing the army while
	// the base is overrun is what loses it in the open. A push already committed
	// continues until the army itself collapses below the bar.
	if (gGodDefendHome == true && gGodPushing == false)
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
	// The comparison is on army power, not on a unit count, so a hero is not one
	// slinger. Committing takes the full margin; holding only takes being ahead.
	int requiredPercent = cGodPushHoldPercent;
	if (gGodPushing == false)
	{
		requiredPercent = cGodPushAdvantagePercent;
	}
	float ourPower = godArmyPower(cMyID);
	float enemyPower = godArmyPower(target);
	if (enemyPower <= 0.0)
	{
		return true; // No enemy army left to stop us.
	}
	float required = (enemyPower * requiredPercent) / 100.0;
	return ourPower >= required;
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

// A stalemate unlocks both win conditions. The engine's own monitors buy Secrets of
// the Titans, place the Gate and build the Wonder; the bot only decides when they are
// allowed. Defending home postpones both, because a long investment would be lost.
void godManageWinConditions(ref StrategyData data)
{
	if (gGodTitanReached == false && kbUnitCount(cUnitTypeAbstractTitan, cMyID, cUnitStateAlive) >= 1)
	{
		gGodTitanReached = true;
		aiEcho("[GodBot] First Titan is out - the Wonder is allowed now.");
	}
	bool ready = gGodStalemate == true && gGodDefendHome == false;
	data.setFlag(cStrategyFlagBuildTitan, ready);
	data.setFlag(cStrategyFlagBuildWonder, ready);
}

// Feeding an army to a Titan just loses the army. While one is on the field and we
// cannot answer it, hold the army at home with the towers and stop raiding.
bool godTitanAllowsAttack()
{
	if (godEnemyTitanID() == -1)
	{
		return true;
	}
	return kbUnitCount(cUnitTypeAbstractTitan, cMyID, cUnitStateAlive) >= 1
		|| aiGetCurrentMilitaryPop() >= cGodTitanHuntArmyPop;
}

// While the base is overrun, the engine keeps more towers per base than its own 2-3.
// Normal hands the number back to the engine.
void godApplyDefence(ref StrategyData data)
{
	if (gGodDefendHome == true)
	{
		data.mTowerAmountPerTCBase = cGodDefendTowersPerBase;
		return;
	}
	data.mTowerAmountPerTCBase = cCalculateNumberTowersAutomatically;
}

// Build one tower at a chosen spot, toward the approach the enemy is using.
int godBuildTowerAt(vector location = cInvalidVector, int baseID = -1)
{
	if (calculateNumPossibleTowersToBuild() < 1)
	{
		return -1; // Already at our tower build limit.
	}
	if (kbGetIsLocationOnMap(location) == false)
	{
		return -1;
	}
	int planID = createLocationBuildPlan(cUnitTypeSentryTower, 1, cGodFrontTowerPriority,
		gMilitaryBuildingsCategoryID, location, 7.5, 2.0);
	if (planID == -1)
	{
		return -1;
	}
	if (baseID != -1)
	{
		aiPlanSetBaseID(planID, baseID);
	}
	return planID;
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
		int age = kbPlayerGetAge(cMyID);
		if (age != gGodLastAge)
		{
			gGodLastAge = age;
			godApplyAttackCadence();
			// The engine re-enables its default strategy flags as the game goes on, so
			// the naval shutdown has to be re-applied at each age, not just at init.
			godApplyNavalPolicy(data);
		}
		// The engine's own serious-trouble signal is the whole defence decision. A
		// per-base threat count is what pinned the army in fortify in a big game.
		bool defend = gDefensivelyOverrun;
		if (defend != gGodDefendHome)
		{
			gGodDefendHome = defend;
			godApplyDefence(data);
			godApplyAttackCadence();
			if (defend == true)
			{
				aiEcho("[GodBot] Holding the base - the army stays home with the towers.");
				// towerManager only re-checks every couple of minutes; nudge it so the
				// extra towers start as soon as the base is overrun.
				xsRuleIgnoreIntervalOnce("towerManager");
			}
			else
			{
				aiEcho("[GodBot] Defend over - the army returns to the engine's defence.");
			}
		}
		godUpdateStalemate();
		godManageWinConditions(data);
		// The engine's attackManager is the only thing that launches attacks. This
		// gate holds it closed while we defend home or an enemy Titan is unanswerable.
		data.setFlag(cStrategyFlagCanAttack,
			gGodDefendHome == false && godTitanAllowsAttack() && godAttackGateOpen());
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

// The push decision reads both armies, so it runs on its own timer rather than in
// the per-second strategy update.
rule godPushMonitor
inactive
minInterval 10
{
	bool pushing = godShouldPush();
	if (pushing == gGodPushing)
	{
		return;
	}
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

// Pull back each attack that is outnumbered on the spot or standing in front of a
// Titan. Every attack is judged on its own, so a failing raid never recalls the main
// army. This keeps running while godTitanAllowsAttack holds new attacks back: an army
// already in the field still comes home.
rule godRetreatMonitor
inactive
minInterval 10
{
	int[] plans = aiPlanGetIDsByType(cPlanAttack);
	for (int i = 0; i < plans.size(); i++)
	{
		int planID = plans[i];
		if (aiPlanGetParentID(planID) != -1)
		{
			continue;
		}
		// The engine tags its Titan plans. A Titan is one unit, so the outnumbered
		// check would recall it on every pass and it would never land.
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
		if (godAttackIsLosing(planID, units.size()) == true)
		{
			godRetreatPlan(planID);
		}
	}
}

// Send part of the army to an ally whose base is being overrun, but only while our
// own bases are quiet and only a capped share of it. This is the one custom plan that
// may claim the land army, and it releases on its own.
rule godAssistMonitor
inactive
minInterval 10
{
	if (aiPlanGetIsIDValid(gGodAssistPlanID) == true)
	{
		bool end = false;
		if (gGodDefendHome == true)
		{
			end = true; // Our own bases come first.
		}
		if (kbPlayerHasLost(gGodAssistAllyID) == true
			|| kbBaseGetIsIDValid(gGodAssistAllyID, gGodAssistBaseID) == false)
		{
			end = true;
		}
		if (end == false)
		{
			vector loc = kbBaseGetLocation(gGodAssistAllyID, gGodAssistBaseID);
			float radius = kbBaseGetDistance(gGodAssistAllyID, gGodAssistBaseID) + cGodThreatExtraRadius;
			float enemy = godPowerNear(cPlayerRelationEnemyNotGaia, loc, radius);
			float allyPower = godPowerNear(gGodAssistAllyID, loc, radius);
			if ((enemy * 100.0) <= (allyPower * cGodAssistRatioPercent))
			{
				if (gGodAssistQuietSince == -1)
				{
					gGodAssistQuietSince = xsGetTime();
				}
				if (xsGetTime() - gGodAssistQuietSince >= cGodAssistQuietSeconds)
				{
					end = true;
				}
			}
			else
			{
				gGodAssistQuietSince = -1;
			}
		}
		if (end == true)
		{
			aiEcho("[GodBot] Assist over - the army returns home.");
			aiPlanDestroy(gGodAssistPlanID);
			gGodAssistPlanID = -1;
			gGodAssistAllyID = -1;
			gGodAssistBaseID = -1;
			gGodAssistQuietSince = -1;
		}
		return;
	}
	if (gGodDefendHome == true)
	{
		return;
	}
	int ally = -1;
	int allyBase = godAssistTarget(ally);
	if (allyBase == -1)
	{
		return;
	}
	int share = (kbUnitCount(cUnitTypeLogicalTypeLandMilitary, cMyID, cUnitStateAlive) * cGodAssistMaxSharePercent) / 100;
	if (share < cGodAssistMinUnits)
	{
		return;
	}
	gGodAssistAllyID = ally;
	gGodAssistBaseID = allyBase;
	gGodAssistPlanID = createDefendPlanForPoint("GodBot Assist",
		kbBaseGetLocation(gGodAssistAllyID, gGodAssistBaseID), cGodAssistPriority);
	if (gGodAssistPlanID == -1)
	{
		return;
	}
	aiPlanAddUnitType(gGodAssistPlanID, cUnitTypeLogicalTypeLandMilitary, cGodAssistMinUnits, share, share);
	aiPlanSetFlag(gGodAssistPlanID, cPlanFlagCantBeStolenFrom, true);
	aiPlanSetVariableFloat(gGodAssistPlanID, cDefendPlanEngageRange, 0,
		kbBaseGetDistance(gGodAssistAllyID, gGodAssistBaseID) + cGodThreatExtraRadius);
	gGodAssistQuietSince = -1;
	aiEcho("[GodBot] Assisting ally " + gGodAssistAllyID + " at base " + gGodAssistBaseID
		+ ", sending up to " + share + " units.");
}

// While the base is overrun, put a tower on the side the enemy is coming from, so
// the approach the engine's random tower ring leaves open is covered. One at a time;
// the engine's towerManager still owns the tower count.
rule godFrontTowerMonitor
inactive
minInterval 30
{
	if (aiPlanGetIsIDValid(gGodFrontTowerPlanID) == false)
	{
		gGodFrontTowerPlanID = -1;
	}
	if (gGodDefendHome == false)
	{
		return;
	}
	if (gGodFrontTowerPlanID != -1)
	{
		return; // One front tower at a time.
	}
	// The engine already tracks enemy power per defend base on a 5s timer.
	int baseID = -1;
	int worst = 0;
	for (int i = 0; i < gDefendTCBases.size(); i++)
	{
		int power = gEnemyPowerInBases[i];
		if (power > worst)
		{
			worst = power;
			baseID = gDefendTCBases[i];
		}
	}
	if (baseID == -1 || worst < cGodThreatMinPower)
	{
		return;
	}
	vector baseLoc = kbBaseGetLocation(cMyID, baseID);
	int queryID = useSimpleUnitQuery(cUnitTypeLogicalTypeLandMilitary, cPlayerRelationEnemyNotGaia,
		cUnitStateAlive, baseLoc, godBaseThreatRadius(baseID));
	kbUnitQueryExecute(queryID);
	int[] units = kbUnitQueryGetResults(queryID);
	if (units.size() == 0)
	{
		return;
	}
	// The average direction to the enemy gives the side they are massing from.
	vector away = vector(0.0, 0.0, 0.0);
	int counted = 0;
	for (int i = 0; i < units.size(); i++)
	{
		if (kbUnitGetIsIDValid(units[i]) == false)
		{
			continue;
		}
		away = away + (kbUnitGetPosition(units[i]) - baseLoc);
		counted++;
	}
	if (counted == 0)
	{
		return;
	}
	vector spot = baseLoc + xsVectorNormalize(away) * cGodFrontTowerDistance;
	gGodFrontTowerPlanID = godBuildTowerAt(spot, baseID);
	if (gGodFrontTowerPlanID != -1)
	{
		aiEcho("[GodBot] Front tower toward the enemy at " + spot + ".");
	}
}

// One raid at a time, and only when we cannot commit to a real attack. Cavalry goes
// for the gold mine the enemy is working; the foot party goes for the drop site the
// enemy left open. A raid is never a reason to split the army while pushing.
rule godRaidMonitor
inactive
minInterval 60
{
	if (gGodDefendHome == true)
	{
		return;
	}
	// The strategy flag is the engine's attackManager gate; a raid reads our
	// willingness to fight instead.
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
	// Cavalry outruns the defence, so it is the first choice while it is available.
	if (kbUnitCount(cUnitTypeAbstractCavalry, cMyID, cUnitStateAlive) >= cGodCavRaidMinCavalry)
	{
		int mine = godFindGoldMineTarget();
		if (mine != -1)
		{
			vector raidPoint = kbUnitGetPosition(mine);
			godLaunchRaid("GodBot Cavalry Raid", raidPoint, cUnitTypeAbstractCavalry, 3, 6, 15, true);
			aiEcho("[GodBot] Cavalry raiding the enemy gold at " + raidPoint + ".");
			return;
		}
	}
	// Only raid with spare army; otherwise stay massed for the main attack.
	int[] homeUnits = aiPlanGetUnits(gPrimaryLandDefendPlan);
	if (kbUnitsGetPower(homeUnits, true) < 10)
	{
		return;
	}
	int site = godFindRaidTarget(target);
	if (site == -1)
	{
		return;
	}
	vector raidPoint = kbUnitGetPosition(site);
	godLaunchRaid("GodBot Raid", raidPoint, cUnitTypeLogicalTypeLandMilitary, 4, 8, 20, false);
	aiEcho("[GodBot] Raiding enemy economy at " + raidPoint + ".");
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
	int underAttack = 0;
	if (godUnderAttack() == true)
	{
		underAttack = 1;
	}
	int defend = 0;
	if (gGodDefendHome == true)
	{
		defend = 1;
	}
	int assist = -1;
	if (aiPlanGetIsIDValid(gGodAssistPlanID) == true)
	{
		assist = gGodAssistAllyID;
	}
	aiEcho("[GBOT] t=" + xsGetTime()
		+ " age=" + kbPlayerGetAge(cMyID)
		+ " vills=" + kbUnitCount(cUnitTypeAbstractVillager, cMyID, cUnitStateAlive)
		+ " pop=" + kbPlayerGetPop(cMyID) + "/" + kbPlayerGetPopCap(cMyID)
		+ " army=" + aiGetCurrentMilitaryPop()
		+ " food=" + xsFloatToInt(kbResourceGet(cResourceFood))
		+ " wood=" + xsFloatToInt(kbResourceGet(cResourceWood))
		+ " gold=" + xsFloatToInt(kbResourceGet(cResourceGold))
		+ " favor=" + xsFloatToInt(kbResourceGet(cResourceFavor))
		+ " enemyAge=" + enemyAge
		+ " enemyTitan=" + enemyTitan
		+ " titans=" + kbUnitCount(cUnitTypeAbstractTitan, cMyID, cUnitStateAlive)
		+ " wonder=" + kbUnitCount(cUnitTypeWonder, cMyID, cUnitStateAlive)
		+ " state=" + state
		+ " underAttack=" + underAttack
		+ " enemies=" + gGodEnemyCount
		+ " allies=" + gGodAllyCount
		+ " defend=" + defend
		+ " assist=" + assist);
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
	xsEnableRule("godPushMonitor");
	xsEnableRule("godRetreatMonitor");
	xsEnableRule("godAssistMonitor");
	xsEnableRule("godFrontTowerMonitor");
	xsEnableRule("godRaidMonitor");
	xsEnableRule("godTelemetryMonitor");
}
