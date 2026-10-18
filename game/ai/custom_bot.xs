//==============================================================================
// custom_bot.xs - Age of Mythology: Retold Custom AI Bot
//
// A Conqueror-flavoured bot: slow, territorial, economy-heavy. Behaviour is
// declared here and the engine's plan system executes it. See
// docs/custom-bot-design.md for the requirements this implements and how each
// one is translated into engine behaviour.
//==============================================================================
include "core/main.xs";

//==============================================================================
// Tunables
//==============================================================================
// Conqueror already attacks on a slow rhythm; we slow it down further.
const float cCustomCadenceMultiplier = 1.5;

// Tiny maps: how much free pop we want before the Armory is allowed.
const int cCustomHousePopHeadroomBase = 15;

// Retreat: abandon an attack after losing this share of the army ...
const int cCustomRetreatLossPercent = 50;
// ... within this many seconds, or when the enemy outnumbers us by this ratio.
const int cCustomRetreatLossWindow = 45;
const int cCustomRetreatEnemyRatioPercent = 150;

// Decisive push: once we are clearly ahead, attack on a fast cadence instead.
const int cCustomPushArmyPop = 40;   // military pop required before we commit
const int cCustomPushInterval = 90;  // seconds between attacks while pushing

// Economy: Conqueror-style boom target for the villager count.
const int cCustomMaxVillagerPop = 90;

//==============================================================================
// State
//==============================================================================
bool gCustomNavalMap = false;
bool gCustomPushing = false;
int gCustomLastAge = -1;
int gCustomRetreatSamplePop = -1;
int gCustomRetreatSampleTime = 0;
bool gCustomHeldTitanGate = false;

//==============================================================================
// Helpers
//==============================================================================

// A map only counts as naval if it is an island map or we start on a transport.
bool customIsNavalMap()
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

bool customUnderAttack()
{
	return gDefensivelyOverrun;
}

// Destroy every build plan for a given building type.
void customCancelBuildPlans(int puid = -1)
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

bool customBaseHasMilitaryBuilding(int baseID = -1)
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

int customPickMilitaryBuilding()
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
int customNextTowerUpgrade()
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

// Prefer an enemy drop site to hit their economy; fall back to any villager.
int customFindRaidTarget(int target = -1)
{
	int[] dropSites = new int(4, -1);
	dropSites[0] = cUnitTypeStorehouse;
	dropSites[1] = cUnitTypeGranary;
	dropSites[2] = cUnitTypeLumberCamp;
	dropSites[3] = cUnitTypeOxCartBuilding;
	for (int i = 0; i < dropSites.size(); i++)
	{
		int unitID = getUnit(dropSites[i], target, cUnitStateAlive);
		if (unitID != -1)
		{
			return unitID;
		}
	}
	return getUnit(cUnitTypeAbstractVillager, target, cUnitStateAlive);
}

void customRetreatArmy()
{
	int[] plans = aiPlanGetIDsByType(cPlanAttack);
	for (int i = 0; i < plans.size(); i++)
	{
		int planID = plans[i];
		if (aiPlanGetParentID(planID) != -1)
		{
			continue;
		}
		aiPlanSetState(planID, cPlanStateDone);
	}
	// Don't immediately walk back out; regroup first.
	gAttackManager.mLastAttackTime = xsGetTime();
}

//==============================================================================
// Strategy policy
//==============================================================================

// A Conqueror booms: ask for a large villager count to fund a slow push.
void customApplyEconomy()
{
	gOverrideMaxVillagerPop = cCustomMaxVillagerPop;
}

void customSetMinorGods(int classical = -1, int heroic = -1, int mythic = -1)
{
	gOverrideClassicalMinorGod = classical;
	gOverrideHeroicMinorGod = heroic;
	gOverrideMythicMinorGod = mythic;
}

// Per major god, pick the minor gods that best suit an economy-first,
// defence-minded, slow-push style. The engine ignores an override it cannot
// obtain, so keying on the major god guarantees the pick is valid. The
// reasoning behind each pick (and the god matchups) is in
// docs/custom-bot-minor-gods.md.
void customApplyMinorGods()
{
	switch (cMyCiv)
	{
		// Greeks.
		case cCivZeus:
		{
			customSetMinorGods(cTechClassicalAgeAthena, cTechHeroicAgeApollo, cTechMythicAgeHephaestus);
			break;
		}
		case cCivPoseidon:
		{
			customSetMinorGods(cTechClassicalAgeAres, cTechHeroicAgeAphrodite, cTechMythicAgeHephaestus);
			break;
		}
		case cCivHades:
		{
			customSetMinorGods(cTechClassicalAgeAthena, cTechHeroicAgeAphrodite, cTechMythicAgeHephaestus);
			break;
		}
		case cCivDemeter:
		{
			customSetMinorGods(cTechClassicalAgePan, cTechHeroicAgeHestia, cTechMythicAgeHera);
			break;
		}
		// Egyptians.
		case cCivRa:
		{
			customSetMinorGods(cTechClassicalAgeBast, cTechHeroicAgeSekhmet, cTechMythicAgeHorus);
			break;
		}
		case cCivIsis:
		{
			customSetMinorGods(cTechClassicalAgeBast, cTechHeroicAgeNephthys, cTechMythicAgeThoth);
			break;
		}
		case cCivSet:
		{
			customSetMinorGods(cTechClassicalAgePtah, cTechHeroicAgeSekhmet, cTechMythicAgeHorus);
			break;
		}
		// Norse.
		case cCivThor:
		{
			customSetMinorGods(cTechClassicalAgeForseti, cTechHeroicAgeSkadi, cTechMythicAgeTyr);
			break;
		}
		case cCivOdin:
		{
			customSetMinorGods(cTechClassicalAgeHeimdall, cTechHeroicAgeSkadi, cTechMythicAgeTyr);
			break;
		}
		case cCivLoki:
		{
			customSetMinorGods(cTechClassicalAgeHeimdall, cTechHeroicAgeBragi, cTechMythicAgeTyr);
			break;
		}
		case cCivFreyr:
		{
			customSetMinorGods(cTechClassicalAgeUllr, cTechHeroicAgeAegir, cTechMythicAgeVidar);
			break;
		}
		// Atlanteans.
		case cCivKronos:
		{
			customSetMinorGods(cTechClassicalAgePrometheus, cTechHeroicAgeRheia, cTechMythicAgeAtlas);
			break;
		}
		case cCivOranos:
		{
			customSetMinorGods(cTechClassicalAgeOceanus, cTechHeroicAgeHyperion, cTechMythicAgeHekate);
			break;
		}
		case cCivGaia:
		{
			customSetMinorGods(cTechClassicalAgeOceanus, cTechHeroicAgeRheia, cTechMythicAgeAtlas);
			break;
		}
		// Chinese.
		case cCivFuxi:
		{
			customSetMinorGods(cTechClassicalAgeXuannu, cTechHeroicAgeNuba, cTechMythicAgeHuangdi);
			break;
		}
		case cCivNuwa:
		{
			customSetMinorGods(cTechClassicalAgeHoutu, cTechHeroicAgeRushou, cTechMythicAgeZhurong);
			break;
		}
		case cCivShennong:
		{
			customSetMinorGods(cTechClassicalAgeHoutu, cTechHeroicAgeRushou, cTechMythicAgeHuangdi);
			break;
		}
		// Japanese.
		case cCivAmaterasu:
		{
			customSetMinorGods(cTechClassicalAgeAmeNoUzume, cTechHeroicAgeHachiman, cTechMythicAgeTakemikazuchi);
			break;
		}
		case cCivTsukuyomi:
		{
			customSetMinorGods(cTechClassicalAgeAmeNoUzume, cTechHeroicAgeHachiman, cTechMythicAgeOkuninushi);
			break;
		}
		case cCivSusanoo:
		{
			customSetMinorGods(cTechClassicalAgeMinakatatomi, cTechHeroicAgeRaijin, cTechMythicAgeTakemikazuchi);
			break;
		}
		// Aztecs.
		case cCivHuitzilopochtli:
		{
			customSetMinorGods(cTechClassicalAgePatecatl, cTechHeroicAgeCoatlicue, cTechMythicAgeTlaloc);
			break;
		}
		case cCivTezcatlipoca:
		{
			customSetMinorGods(cTechClassicalAgeHuehuecoyotl, cTechHeroicAgeCoyolxauhqui, cTechMythicAgeXolotl);
			break;
		}
		case cCivQuetzalcoatl:
		{
			customSetMinorGods(cTechClassicalAgePatecatl, cTechHeroicAgeCoatlicue, cTechMythicAgeTlaloc);
			break;
		}
	}
	aiEcho("[CustomBot] Minor gods: " + kbTechGetName(gOverrideClassicalMinorGod) + " / "
		+ kbTechGetName(gOverrideHeroicMinorGod) + " / " + kbTechGetName(gOverrideMythicMinorGod) + ".");
}

// No navy unless the map is really naval; otherwise shut naval military down.
void customApplyNavalPolicy(ref StrategyData data)
{
	gCustomNavalMap = customIsNavalMap();
	if (gCustomNavalMap == true)
	{
		aiEcho("[CustomBot] Naval map detected - keeping a navy.");
		return;
	}
	aiEcho("[CustomBot] Not a naval map - disabling naval military.");
	data.setFlag(cStrategyFlagAutoTrainNavalMilitaryUnits, false);
	data.setFlag(cStrategyFlagCanNavalAttack, false);
	data.setFlag(cStrategyFlagCanNavalDefend, false);
	data.setFlag(cStrategyFlagAutomaticNavalScouting, false);
	data.setFlag(cStrategyFlagMaintainNavalTransport, false);
	gOverrideNavalMaxMilitaryPop = 0;
}

// Conqueror's slow rhythm, slowed down further; faster once we are pushing.
void customApplyAttackCadence()
{
	int interval = 0;
	if (gCustomPushing == true)
	{
		interval = cCustomPushInterval;
	}
	else
	{
		interval = xsFloatToInt(selectByDifficultyFloat(20, 15, 9, 7, 5, 5) * 60.0 * cCustomCadenceMultiplier);
	}
	gAttackManager.mBaseAttackInterval = interval;
	gAttackManager.mAttackInterval = interval;
	gNavalAttackManager.mBaseAttackInterval = interval;
	gNavalAttackManager.mAttackInterval = interval;
	aiEcho("[CustomBot] Attack interval set to " + interval + " seconds.");
}

// Are we clearly ahead enough to commit to a decisive push? Conservative on
// purpose: we only stop being patient once the game is effectively won.
bool customShouldPush()
{
	if (customUnderAttack() == true)
	{
		return false;
	}
	int age = kbPlayerGetAge(cMyID);
	if (age < cAge3)
	{
		return false; // Don't commit before Heroic.
	}
	if (aiGetCurrentMilitaryPop() < cCustomPushArmyPop)
	{
		return false;
	}
	int target = aiGetMostHatedPlayerID();
	if (target == -1)
	{
		return false;
	}
	// The enemy is crumbling: one base left.
	if (kbUnitCount(cUnitTypeAbstractTownCenter, target, cUnitStateAlive) <= 1)
	{
		return true;
	}
	// We are an age ahead and have a real army.
	if (age > kbPlayerGetAge(target))
	{
		return true;
	}
	return false;
}

// On Tiny maps we want houses before the Armory: hold the Armory until the
// Temple is up and we have a comfortable pop buffer, pushing houses meanwhile.
void customManageTinyMapHousing(ref StrategyData data)
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
	bool enoughHouses = housesMaxed || popHeadroom >= cCustomHousePopHeadroomBase + 5 * age;

	if (templeBuilt == true && enoughHouses == false)
	{
		data.setFlag(cStrategyFlagBuildArmory, false);
		customCancelBuildPlans(gArmoryUnit);
		customPushHouseBuild();
		return;
	}
	data.setFlag(cStrategyFlagBuildArmory, true);
}

void customPushHouseBuild()
{
	if (aiPlanGetNumberByTypeAndVariableIntValue(cPlanBuild, cBuildPlanBuildingTypeID, gHouseUnit) > 0)
	{
		return;
	}
	int baseID = getRandomTownCenterBaseID();
	createSimpleBuildPlan(gHouseUnit, 1, 96, gEconomicBuildingsCategoryID, baseID, 1);
}

// While we're being pushed, don't start or keep a Wonder, and postpone an
// uncommitted Titan Gate. Resources fall back to the normal build rules.
void customManageWonderAndTitanGate(ref StrategyData data)
{
	if (customUnderAttack() == true)
	{
		data.setFlag(cStrategyFlagBuildWonder, false);
		customCancelBuildPlans(cUnitTypeWonder);
		customHoldTitanGate();
		return;
	}
	data.setFlag(cStrategyFlagBuildWonder, true);
	customReleaseTitanGate();
}

void customHoldTitanGate()
{
	if (xsIsRuleEnabled("titanGateConstructionMonitor") == false)
	{
		return;
	}
	if (gTitanGateCurrentState != cStateBegin && gTitanGateCurrentState != cStateWaitingForFoundation)
	{
		return;
	}
	aiEcho("[CustomBot] Under attack - postponing the Titan Gate.");
	if (aiPlanGetIsIDValid(gTitanGatePlanID) == true)
	{
		aiPlanDestroy(gTitanGatePlanID);
	}
	gTitanGatePlanID = -1;
	gTitanGateCurrentState = cStateBegin;
	xsDisableRule("titanGateConstructionMonitor");
	gCustomHeldTitanGate = true;
}

void customReleaseTitanGate()
{
	if (gCustomHeldTitanGate == false)
	{
		return;
	}
	gCustomHeldTitanGate = false;
	if (kbGodPowerGetCost(cProtoPowerTitanGate, cMyID) != 0.0)
	{
		return;
	}
	xsEnableRule("titanGateConstructionMonitor");
	xsRuleIgnoreIntervalOnce("titanGateConstructionMonitor");
}

//==============================================================================
// Strategy
//==============================================================================
Strategy customBotStrategy()
{
	Strategy strategy;
	strategy.mID = cStrategySPCCustom;
	strategy.mAge = cAge1;
	strategy.mName = "Custom Conqueror";

	strategy.mInitFunc = [](ref StrategyData data) -> bool
	{
		aiEcho("=== [CustomBot] strategy init ===");
		data.enableAllStrategyFlags();
		customApplyNavalPolicy(data);
		customApplyAttackCadence();
		gCustomLastAge = kbPlayerGetAge(cMyID);
		return true;
	};

	// Runs every second. Returning false would end the strategy, so always true.
	strategy.mUpdateFunc = [](ref StrategyData data) -> bool
	{
		int age = kbPlayerGetAge(cMyID);
		if (age != gCustomLastAge)
		{
			gCustomLastAge = age;
			customApplyAttackCadence();
		}
		bool pushing = customShouldPush();
		if (pushing != gCustomPushing)
		{
			gCustomPushing = pushing;
			if (pushing == true)
			{
				aiEcho("[CustomBot] Committed to a decisive push.");
			}
			else
			{
				aiEcho("[CustomBot] Back to the slow rhythm.");
			}
			customApplyAttackCadence();
		}
		customManageTinyMapHousing(data);
		customManageWonderAndTitanGate(data);
		return true;
	};

	return strategy;
}

void customBotStrategySetup()
{
	Strategy strategy = customBotStrategy();
	gStrategyManager.addStrategy(strategy);
}

//==============================================================================
// Monitors
//==============================================================================

// Scrap any warships that slip through when the map isn't a naval one.
rule customNavalCleanupMonitor
inactive
minInterval 30
{
	if (gCustomNavalMap == true)
	{
		return;
	}
	int[] warships = new int(0, -1);
	int queryID = kbUnitQueryCreate("CustomBot warships");
	kbUnitQuerySetPlayerID(queryID, cMyID, false);
	kbUnitQuerySetUnitType(queryID, cUnitTypeLogicalTypeNavalMilitary);
	kbUnitQuerySetState(queryID, cUnitStateAlive);
	int num = kbUnitQueryExecute(queryID);
	for (int i = 0; i < num; i++)
	{
		warships.add(kbUnitQueryGetResult(queryID, i));
	}
	if (warships.size() > 0)
	{
		aiEcho("[CustomBot] Not a naval map - scrapping " + warships.size() + " warship(s).");
		aiTaskDeleteUnits(warships);
	}
}

// Every village (TC base) gets one Temple and one military building.
rule customVillageMonitor
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
		if (customBaseHasMilitaryBuilding(baseID) == false)
		{
			int puid = customPickMilitaryBuilding();
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
rule customTowerUpgradeMonitor
inactive
minInterval 10
{
	if (cGameModeCurrent == cGameModeDeathmatch)
	{
		xsDisableRule("customTowerUpgradeMonitor");
		return;
	}
	if (cDifficultyCurrent == cDifficultyEasy)
	{
		xsDisableRule("customTowerUpgradeMonitor");
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
	if (areAtMaxConcurrentResearchPlans("customTowerUpgradeMonitor") == true)
	{
		return;
	}
	int tech = customNextTowerUpgrade();
	if (tech == -1)
	{
		return;
	}
	aiEcho("[CustomBot] Researching tower upgrade: " + kbTechGetName(tech) + ".");
	gTowerOffensiveResearchPlanID = researchSimpleTech(tech, cUnitTypeSentryTower, -1, 70);
	aiPlanSetEventHandler(gTowerOffensiveResearchPlanID, cPlanEventStateChange, "resetOffensiveTowerResearchPlan");
}

// Retreat when an attack is bleeding out or we're outnumbered on the spot.
rule customRetreatMonitor
inactive
minInterval 10
{
	if (checkStrategyFlag(cStrategyFlagCanAttack) == false)
	{
		return;
	}
	int[] plans = aiPlanGetIDsByType(cPlanAttack);
	int ourCount = 0;
	int ourPop = 0;
	vector planLoc = cInvalidVector;
	bool engaged = false;
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
		ourCount += units.size();
		ourPop += kbUnitsGetPower(units, true);
		planLoc = aiPlanGetLocation(planID);
		engaged = true;
	}

	if (engaged == false)
	{
		gCustomRetreatSamplePop = -1;
		return;
	}

	int now = xsGetTime();
	bool retreat = false;
	if (gCustomRetreatSamplePop > 0 && (now - gCustomRetreatSampleTime) <= cCustomRetreatLossWindow)
	{
		int lostPop = gCustomRetreatSamplePop - ourPop;
		if (lostPop > 0 && lostPop * 100 >= gCustomRetreatSamplePop * cCustomRetreatLossPercent)
		{
			aiEcho("[CustomBot] Retreating: lost " + lostPop + " of " + gCustomRetreatSamplePop + " pop.");
			retreat = true;
		}
	}
	if (retreat == false && planLoc != cInvalidVector)
	{
		int enemyCount = getUnitCountByLocation(cUnitTypeLogicalTypeLandMilitary, cPlayerRelationEnemyNotGaia,
			cUnitStateAlive, planLoc, 60.0);
		if (enemyCount >= 3 && enemyCount * 100 > ourCount * cCustomRetreatEnemyRatioPercent)
		{
			aiEcho("[CustomBot] Retreating: " + enemyCount + " enemies vs our " + ourCount + ".");
			retreat = true;
		}
	}

	if (retreat == true)
	{
		customRetreatArmy();
		gCustomRetreatSamplePop = -1;
		return;
	}
	gCustomRetreatSamplePop = ourPop;
	gCustomRetreatSampleTime = now;
}

// When we can't commit to a full attack, send a small group to hit the enemy
// economy instead (drop sites first, then villagers).
rule customRaidMonitor
inactive
minInterval 90
{
	if (checkStrategyFlag(cStrategyFlagCanAttack) == false)
	{
		return;
	}
	if (customUnderAttack() == true)
	{
		return;
	}
	if (gCustomPushing == true)
	{
		return; // Don't split the army while committing.
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
	int raidTargetID = customFindRaidTarget(target);
	if (raidTargetID == -1)
	{
		return;
	}
	vector raidPoint = kbUnitGetPosition(raidTargetID);
	vector gatherPoint = aiPlanGetVariableVector(gPrimaryLandDefendPlan, cDefendPlanGatherPoint, 0);
	int planID = aiPlanCreate("CustomBot Raid", cPlanAttack, -1, gMilitaryAttackingCategoryID);
	aiPlanSetVariableInt(planID, cAttackPlanTargetMode, 0, cAttackPlanTargetModePoint);
	aiPlanSetVariableVector(planID, cAttackPlanTargetPoint, 0, raidPoint);
	aiPlanSetVariableVector(planID, cAttackPlanGatherPoint, 0, gatherPoint);
	aiPlanSetVariableFloat(planID, cAttackPlanGatherDistance, 0, 15.0);
	aiPlanSetVariableInt(planID, cAttackPlanGatherWaitTime, 0, 20 * 1000);
	aiPlanSetVariableInt(planID, cAttackPlanDoneMode, 0, cAttackPlanDoneModeNoTarget | cAttackPlanDoneModeNoUnits);
	aiPlanAddUnitType(planID, cUnitTypeLogicalTypeLandMilitary, 2, 4, 8);
	setDefaultAttackPlanTargetUnitTypes(planID);
	aiPlanSetPriority(planID, 70);
	aiEcho("[CustomBot] Raiding enemy economy at " + raidPoint + ".");
}

// One structured line every 30s for offline analysis. Read it back from
// temp/Logs/MythRetoldAIOutputPlayer<N>.txt; see AGENTS.md.
rule customTelemetryMonitor
inactive
minInterval 30
{
	int target = aiGetMostHatedPlayerID();
	int enemyAge = -1;
	if (target != -1)
	{
		enemyAge = kbPlayerGetAge(target);
	}
	string state = "hold";
	if (gCustomPushing == true)
	{
		state = "push";
	}
	else if (customUnderAttack() == true)
	{
		state = "defend";
	}
	aiEcho("[CBOT] t=" + xsGetTime()
		+ " age=" + kbPlayerGetAge(cMyID)
		+ " vills=" + kbUnitCount(cUnitTypeAbstractVillager, cMyID, cUnitStateAlive)
		+ " pop=" + kbPlayerGetPop(cMyID) + "/" + kbPlayerGetPopCap(cMyID)
		+ " army=" + aiGetCurrentMilitaryPop()
		+ " food=" + xsFloatToInt(kbResourceGet(cResourceFood))
		+ " wood=" + xsFloatToInt(kbResourceGet(cResourceWood))
		+ " gold=" + xsFloatToInt(kbResourceGet(cResourceGold))
		+ " enemyAge=" + enemyAge
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
	aiEcho("=== [CustomBot] preInit() - installing Conqueror strategy ===");
	customApplyEconomy();
	customApplyMinorGods();
	setOverrideStrategy(customBotStrategySetup);
}

//==============================================================================
/*	postInit()

	This function is called in main() after the normal initialization is
	complete. Use it to override settings, build orders, or army plans.
*/
//==============================================================================
void postInit()
{
	aiEcho("=== [CustomBot] postInit() - activating monitors ===");
	xsEnableRule("customNavalCleanupMonitor");
	xsEnableRule("customVillageMonitor");
	xsEnableRule("customTowerUpgradeMonitor");
	xsEnableRule("customRetreatMonitor");
	xsEnableRule("customRaidMonitor");
	xsEnableRule("customTelemetryMonitor");
}
