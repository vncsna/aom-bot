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

// Tiny maps: how much free pop we want before the Armory is allowed.
const int cGodHousePopHeadroomBase = 15;

// Retreat: abandon an attack after losing this share of the army ...
const int cGodRetreatLossPercent = 50;
// ... within this many seconds, or when the enemy outnumbers us by this ratio.
const int cGodRetreatLossWindow = 45;
const int cGodRetreatEnemyRatioPercent = 150;

// A raid is a small group, so a whole base garrison counts as "outnumbered" and
// calls it off before it lands. Judge a raid only on the troops sitting on its
// target, and prefer the target the enemy is not sitting on.
const float cGodRaidTargetRadius = 30.0;
const float cGodRaidAbortRadius = 25.0;

// The enemy's Titan: anything we send at a base while it is out feeds it, so call
// off an attack when it is this close, and only commit again with an army that
// can actually take one on.
const float cGodTitanFleeRadius = 45.0;
const int cGodTitanHuntArmyPop = 60;

// Decisive push: once we are clearly ahead, attack on a fast cadence instead.
const int cGodPushArmyPop = 40;   // military pop required before we commit
const int cGodPushInterval = 90;  // seconds between attacks while pushing
// The bot reads the enemy's army without scouting, so "clearly ahead" can mean
// this much more army than theirs rather than a guess.
const int cGodPushAdvantagePercent = 150;

// Economy: Conqueror-style boom target for the villager count.
const int cGodMaxVillagerPop = 90;

//==============================================================================
// State
//==============================================================================
bool gGodNavalMap = false;
bool gGodPushing = false;
int gGodLastAge = -1;
// Per attack plan in the field: its army power at the start of the loss window, and when.
int[] gGodRetreatPlanIDs = default;
int[] gGodRetreatSamplePops = default;
int[] gGodRetreatSampleTimes = default;
bool gGodHeldTitanGate = false;
int gGodRaidPlanID = -1;

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
int godEnemyMilitaryNear(vector location, float radius = 60.0)
{
	return getUnitCountByLocation(cUnitTypeLogicalTypeLandMilitary, cPlayerRelationEnemyNotGaia,
		cUnitStateAlive, location, radius);
}

// Prefer the enemy drop site the enemy can least defend; fall back to any
// villager. The bot counts the troops at each one without scouting them.
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
	if (bestUnit != -1)
	{
		return bestUnit;
	}
	return getUnit(cUnitTypeAbstractVillager, target, cUnitStateAlive);
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

// A Titan counts as one enemy unit, so the outnumbered check never sees it coming.
bool godTitanNear(vector location)
{
	return getUnitCountByLocation(cUnitTypeAbstractTitan, cPlayerRelationEnemyNotGaia,
		cUnitStateAlive, location, cGodTitanFleeRadius) > 0;
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
	// shouldn't hold up the main attack.
	if (planID != gGodRaidPlanID)
	{
		gAttackManager.mLastAttackTime = xsGetTime();
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

// Conqueror's slow rhythm, slowed down further; faster once we are pushing.
void godApplyAttackCadence()
{
	int interval = 0;
	if (gGodPushing == true)
	{
		interval = cGodPushInterval;
	}
	else
	{
		interval = xsFloatToInt(selectByDifficultyFloat(20, 15, 9, 7, 5, 5) * 60.0 * cGodCadenceMultiplier);
	}
	gAttackManager.mBaseAttackInterval = interval;
	gAttackManager.mAttackInterval = interval;
	gNavalAttackManager.mBaseAttackInterval = interval;
	gNavalAttackManager.mAttackInterval = interval;
	aiEcho("[GodBot] Attack interval set to " + interval + " seconds.");
}

// Are we clearly ahead enough to commit to a decisive push? Conservative on
// purpose: we only stop being patient once the game is effectively won.
bool godShouldPush()
{
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
	// rather than waiting for a base count to prove it.
	int ourArmy = kbUnitCount(cUnitTypeLogicalTypeLandMilitary, cMyID, cUnitStateAlive);
	int enemyArmy = kbUnitCount(cUnitTypeLogicalTypeLandMilitary, target, cUnitStateAlive);
	// No enemy army left to stop us.
	if (enemyArmy == 0)
	{
		return true;
	}
	int required = (enemyArmy * cGodPushAdvantagePercent) / 100;
	if (ourArmy >= required)
	{
		return true;
	}
	return false;
}

void godPushHouseBuild()
{
	if (aiPlanGetNumberByTypeAndVariableIntValue(cPlanBuild, cBuildPlanBuildingTypeID, gHouseUnit) > 0)
	{
		return;
	}
	int baseID = getRandomTownCenterBaseID();
	createSimpleBuildPlan(gHouseUnit, 1, 96, gEconomicBuildingsCategoryID, baseID, 1);
}

// On Tiny maps we want houses before the Armory: hold the Armory until the
// Temple is up and we have a comfortable pop buffer, pushing houses meanwhile.
void godManageTinyMapHousing(ref StrategyData data)
{
	if (cRandomMapName != "tiny")
	{
		return;
	}
	bool templeBuilt = kbUnitCount(cUnitTypeTemple, cMyID, cUnitStateAlive) >= 1;
	int age = kbPlayerGetAge(cMyID);
	int popHeadroom = kbPlayerGetPopCap(cMyID) - kbPlayerGetPop(cMyID);
	bool housesMaxed = false;
	int houseLimit = kbPlayerGetProtoStatInt(cMyID, gHouseUnit, cProtoStatBuildLimit);
	if (houseLimit > 0 && buildingGetNumberAliveAndPlanned(gHouseUnit) >= houseLimit)
	{
		housesMaxed = true;
	}
	bool enoughHouses = housesMaxed || popHeadroom >= cGodHousePopHeadroomBase + 5 * age;

	if (templeBuilt == true && enoughHouses == false)
	{
		data.setFlag(cStrategyFlagBuildArmory, false);
		godCancelBuildPlans(gArmoryUnit);
		godPushHouseBuild();
		return;
	}
	data.setFlag(cStrategyFlagBuildArmory, true);
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

// While we're being pushed, don't start or keep a Wonder, and don't commit to a
// Titan Gate. Resources fall back to the normal build rules.
void godManageWonderAndTitanGate(ref StrategyData data)
{
	bool attacked = godUnderAttack();
	data.setFlag(cStrategyFlagBuildWonder, attacked == false);
	data.setFlag(cStrategyFlagBuildTitan, attacked == false);
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
void godApplyTitanPolicy(ref StrategyData data)
{
	if (godEnemyTitanID() == -1)
	{
		data.setFlag(cStrategyFlagCanAttack, true);
		return;
	}
	bool canKillIt = kbUnitCount(cUnitTypeAbstractTitan, cMyID, cUnitStateAlive) >= 1
		|| aiGetCurrentMilitaryPop() >= cGodTitanHuntArmyPop;
	data.setFlag(cStrategyFlagCanAttack, canKillIt);
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
		godManageTinyMapHousing(data);
		godManageWonderAndTitanGate(data);
		godApplyTitanPolicy(data);
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
		aiEcho("[GodBot] Not a naval map - scrapping " + warships.size() + " warship(s).");
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
// godApplyTitanPolicy holds attacks back: an army already in the field still
// comes home.
rule godRetreatMonitor
inactive
minInterval 10
{
	int now = xsGetTime();
	int[] planIDs = new int(0, -1);
	int[] samplePops = new int(0, -1);
	int[] sampleTimes = new int(0, -1);
	int[] plans = aiPlanGetIDsByType(cPlanAttack);
	for (int i = 0; i < plans.size(); i++)
	{
		int planID = plans[i];
		if (aiPlanGetParentID(planID) != -1)
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
		// Keep a plan's sample until its window has passed, so losses add up across checks.
		int samplePop = ourPop;
		int sampleTime = now;
		int index = gGodRetreatPlanIDs.find(planID);
		if (index != -1 && (now - gGodRetreatSampleTimes[index]) <= cGodRetreatLossWindow)
		{
			samplePop = gGodRetreatSamplePops[index];
			sampleTime = gGodRetreatSampleTimes[index];
		}
		if (godAttackIsLosing(planID, units.size(), ourPop, samplePop) == true)
		{
			godRetreatPlan(planID);
			continue;
		}
		planIDs.add(planID);
		samplePops.add(samplePop);
		sampleTimes.add(sampleTime);
	}
	// Plans that ended or left the field drop out of the samples here.
	gGodRetreatPlanIDs = planIDs;
	gGodRetreatSamplePops = samplePops;
	gGodRetreatSampleTimes = sampleTimes;
}

// When we can't commit to a full attack, send a small group to hit the enemy
// economy instead (drop sites first, then villagers).
rule godRaidMonitor
inactive
minInterval 90
{
	if (checkStrategyFlag(cStrategyFlagCanAttack) == false)
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
	if (aiPlanGetIsIDValid(gGodRaidPlanID) == true)
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
	vector gatherPoint = aiPlanGetVariableVector(gPrimaryLandDefendPlan, cDefendPlanGatherPoint, 0);
	int planID = aiPlanCreate("GodBot Raid", cPlanAttack, -1, gMilitaryAttackingCategoryID);
	aiPlanSetVariableInt(planID, cAttackPlanTargetMode, 0, cAttackPlanTargetModePoint);
	aiPlanSetVariableVector(planID, cAttackPlanTargetPoint, 0, raidPoint);
	aiPlanSetVariableVector(planID, cAttackPlanGatherPoint, 0, gatherPoint);
	aiPlanSetVariableFloat(planID, cAttackPlanGatherDistance, 0, 15.0);
	aiPlanSetVariableInt(planID, cAttackPlanGatherWaitTime, 0, 20 * 1000);
	aiPlanSetVariableInt(planID, cAttackPlanDoneMode, 0, cAttackPlanDoneModeNoTarget | cAttackPlanDoneModeNoUnits);
	aiPlanAddUnitType(planID, cUnitTypeLogicalTypeLandMilitary, 2, 4, 8);
	// Set up like the engine's own attacks: keep builders home, let god powers
	// support the raid, and stop other plans pulling its units away.
	preventSomeBuildersFromJoiningAttack(planID);
	setDefaultAttackPlanTargetUnitTypes(planID);
	addPlanToAllSuitableGodpowerPlans(planID);
	aiPlanSetPriority(planID, 70);
	aiPlanSetFlag(planID, cPlanFlagCantBeStolenFrom, true);
	gGodRaidPlanID = planID;
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
	else if (godUnderAttack() == true)
	{
		state = "defend";
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
		+ " state=" + state);
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
	xsEnableRule("godVillageMonitor");
	xsEnableRule("godTowerUpgradeMonitor");
	xsEnableRule("godRetreatMonitor");
	xsEnableRule("godRaidMonitor");
	xsEnableRule("godTelemetryMonitor");
}
