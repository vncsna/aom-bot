//==============================================================================
// god_bot.xs - Age of Mythology: Retold God Bot
//
// A win-at-all-costs bot: it plays the Conqueror's slow, economy-heavy game but
// decides with information a human player cannot have. See docs/god-bot-design.md
// for the goal and the powers it exploits.
//
// Four responsibilities:
//   1. Economy   - engine auto-eco, villager cap, minor-god picks.
//   2. Defence   - the engine's defend plan and tower manager, untouched.
//   3. Offence   - the engine's attack manager on a deliberately slow cadence.
//   4. Endgame   - the engine's Titan and Wonder monitors, with the two stalls it
//                  leaves behind (the favour sink, a failed Wonder placement) patched.
//
// The land army has one owner: the engine's gPrimaryLandDefendPlan. See the
// complexity budget in AGENTS.md before adding another.
//==============================================================================
include "core/main.xs";

//==============================================================================
// Tunables
//==============================================================================
// Conqueror already attacks on a slow rhythm; we slow it down further. The engine
// randomises the interval on launch and skips its time check on Hard and above once
// the army is large, so the strategy gate holds the rhythm ourselves.
const float cGodCadenceMultiplier = 1.5;

// Decisive push: once we are clearly ahead, attack on a fast cadence instead.
const int cGodPushArmyPop = 40;
const int cGodPushInterval = 90;
// Committing takes the full margin; staying committed only takes still being ahead,
// so a wobble around the threshold cannot flip the cadence back and forth.
const int cGodPushAdvantagePercent = 150;
const int cGodPushHoldPercent = 110;

// Economy: Conqueror-style boom target for the villager count.
const int cGodMaxVillagerPop = 90;

// Retreat an attack that is bleeding out: losing this share of its power within this
// many seconds is a fight it cannot win, whatever the enemy count says.
const int cGodRetreatLossPercent = 50;
const int cGodRetreatLossWindow = 45;
// And retreat one that the enemy on the spot outnumbers by this ratio.
const int cGodRetreatEnemyRatioPercent = 150;

// The enemy's Titan: call an attack off when it is close, and only commit again
// with an army that can actually take one on.
const float cGodTitanFleeRadius = 45.0;
const int cGodTitanHuntArmyPop = 60;

//==============================================================================
// State
//==============================================================================
bool gGodNavalMap = false;
bool gGodPushing = false;
int gGodLastAge = -1;
// Per attack plan in the field: its power at the start of the loss window, and when.
int[] gGodRetreatPlanIDs = default;
int[] gGodRetreatSamplePops = default;
int[] gGodRetreatSampleTimes = default;
bool gGodHoldingFavour = false;
int gGodWonderBaseIndex = -1;

int gGodEnemyCount = 0;
int gGodAllyCount = 0;

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

// Is this attack bleeding out, outnumbered on the spot, or standing in front of a
// Titan?
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
	int enemyCount = godEnemyMilitaryNear(planLoc);
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
	// Don't immediately walk the main army back out; regroup for one interval.
	gAttackManager.mLastAttackTime = xsGetTime();
	gAttackManager.mAttackInterval = godCadenceInterval();
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

// Feeding an army to a Titan just loses the army. While one is on the field and we
// cannot answer it, hold new attacks back and let the engine's defend plan keep the
// army under the towers.
bool godTitanAllowsAttack()
{
	if (godEnemyTitanID() == -1)
	{
		return true;
	}
	return kbUnitCount(cUnitTypeAbstractTitan, cMyID, cUnitStateAlive) >= 1
		|| aiGetCurrentMilitaryPop() >= cGodTitanHuntArmyPop;
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
		// The engine's attackManager is the only thing that launches attacks, and its
		// own defend plan owns the army. This gate holds new attacks back only while
		// an enemy Titan is unanswerable.
		data.setFlag(cStrategyFlagCanAttack, godTitanAllowsAttack() && godAttackGateOpen());
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

// Pull back each attack that is bleeding out, outnumbered on the spot, or standing
// in front of a Titan. Every attack is judged on its own. This keeps running while
// godTitanAllowsAttack holds new attacks back: an army already in the field still
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
		int ourPop = kbUnitsGetPower(units, true);
		// Keep a plan's sample until its window has passed, so losses add up across
		// checks.
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

// Give myth training and god-power rebuys their spending back.
void godReleaseFavour()
{
	if (gGodHoldingFavour == false)
	{
		return;
	}
	gGodHoldingFavour = false;
	xsEnableRule("godPowerRebuyMonitor");
	aiEcho("[GodBot] Titan favour banked - myth training resumes.");
}

// The engine refuses to buy Secrets of the Titans without the favour cost banked, and
// myth training spends every point as it arrives, so the Titan never comes however
// full the other resources are. Hold myth training and god-power rebuys once the
// engine's own bank check passes, until the tech is bought; the refunds are what lets
// the favour accumulate.
rule godFavourReserveMonitor
inactive
minInterval 10
{
	if (kbGodPowerGetNumCharges(cProtoPowerTitanGate, cMyID) >= 1)
	{
		godReleaseFavour();
		return;
	}
	if (kbTechGetStatus(cTechSecretsOfTheTitans) != cTechStatusObtainable)
	{
		godReleaseFavour();
		return;
	}
	// The tech needs the same bank the engine waits for; holding before it would starve
	// the army for a purchase that cannot happen yet.
	if (haveExcessResourceAmount(1500) == false)
	{
		godReleaseFavour();
		return;
	}
	if (gGodHoldingFavour == false)
	{
		gGodHoldingFavour = true;
		xsDisableRule("godPowerRebuyMonitor");
		aiEcho("[GodBot] Holding myth training to bank "
			+ xsFloatToInt(kbTechGetCostPerResource(cTechSecretsOfTheTitans, cResourceFavor))
			+ " favour for the Titan.");
	}
	for (int i = gMythUnitTrainPlans.size() - 1; i >= 0; i--)
	{
		int planID = gMythUnitTrainPlans[i];
		if (aiPlanGetIsIDValid(planID) == true)
		{
			aiPlanDestroy(planID);
		}
	}
}

// The engine places the Wonder in the safest base's back areas only, and a failed
// plan stays failed, so a crowded base stalls the Wonder forever. Replace a failed
// plan with a plain one on the next TC base in the ring; that searches the whole
// base instead of the back areas, and the next failure moves on again.
rule godWonderFallbackMonitor
inactive
minInterval 20
{
	if (kbUnitCount(cUnitTypeWonder, cMyID, cUnitStateAlive) >= 1)
	{
		return;
	}
	int[] plans = aiPlanGetIDsByTypeAndVariableIntValue(cPlanBuild, cBuildPlanBuildingTypeID, cUnitTypeWonder);
	bool failed = false;
	for (int i = 0; i < plans.size(); i++)
	{
		if (aiPlanGetState(plans[i]) != cPlanStateFailed)
		{
			return; // Still placing, or waiting for the resources.
		}
		aiPlanDestroy(plans[i]);
		failed = true;
	}
	if (failed == false)
	{
		return; // The engine has not tried yet.
	}
	if (gDefensivelyOverrun == true)
	{
		return; // A ten-minute investment does not start over a base being overrun.
	}
	int[] bases = new int(0, -1);
	int numBases = kbBaseGetNumber(cMyID);
	for (int i = 0; i < numBases; i++)
	{
		int baseID = kbBaseGetIDByIndex(cMyID, i);
		if (kbBaseIsFlagSet(cMyID, baseID, cBaseFlagTownCenter) == false)
		{
			continue;
		}
		if (gLandAreaGroupID != -1 && kbPathAreAreaGroupsConnected(gLandAreaGroupID,
			kbAreaGroupGetIDByPosition(kbBaseGetLocation(cMyID, baseID)), cPassabilityLand) == false)
		{
			continue;
		}
		bases.add(baseID);
	}
	if (bases.size() == 0)
	{
		return;
	}
	gGodWonderBaseIndex = (gGodWonderBaseIndex + 1) % bases.size();
	createSimpleBuildPlan(cUnitTypeWonder, 1, 99, gEconomicBuildingsCategoryID, bases[gGodWonderBaseIndex]);
	aiEcho("[GodBot] Wonder placement failed - retrying on base " + (gGodWonderBaseIndex + 1) + " of " + bases.size() + ".");
}

// One structured line every 30s for offline analysis. Read it back from
// temp/Logs/MythRetoldAIOutputPlayer<N>.txt; see AGENTS.md.
rule godTelemetryMonitor
inactive
minInterval 30
{
	godCountPlayers();
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
		+ " allies=" + gGodAllyCount);
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
	xsEnableRule("godTowerUpgradeMonitor");
	xsEnableRule("godPushMonitor");
	xsEnableRule("godRetreatMonitor");
	xsEnableRule("godFavourReserveMonitor");
	xsEnableRule("godWonderFallbackMonitor");
	xsEnableRule("godTelemetryMonitor");
}
