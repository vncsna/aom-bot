# Minor Gods

Why the bot picks the minor gods it does, and what each one is good and bad at.

## Why we override at all

Minor gods are the Classical / Heroic / Mythic choices that define a civ's tech tree,
myth units and god power. Left alone, the engine picks one **at random**
(`techs.xs`: `aiGetAgeUpListByIndex(currentAge + 1, xsRandBool() == true ? 0 : 1)`), which
is a coin flip we can win for free.

The overrides `gOverrideClassicalMinorGod` / `gOverrideHeroicMinorGod` /
`gOverrideMythicMinorGod` are **tech IDs** (e.g. `cTechClassicalAgeAthena`). The engine
only uses an override if `kbTechGetStatus(override, false) == cTechStatusObtainable`, so a
pick the current major god cannot get is **silently ignored** and falls back to random —
safe by construction. We key the choice on `cMyCiv` (the major god) so the pick is always
valid.

## The style we build for

Economy first, defence-minded, slow push. Every pick favours at least one of:

- **Economy** — villagers, population, favour, cheaper techs.
- **Defence** — buildings, towers, heroes, ranged units.
- **Late-game power** — armory/unit upgrades, elite infantry, siege.

We avoid navy-oriented and pure-rush gods: the bot has no navy and does not rush.

## Greeks

| Age | God | Focus |
|---|---|---|
| Classical | Athena | Infantry |
| Classical | Hermes | Cavalry |
| Classical | Ares | Foot soldiers |
| Classical | Pan | Defence |
| Heroic | Apollo | Ranged soldiers and vision |
| Heroic | Dionysus | Health and cavalry |
| Heroic | Aphrodite | Villagers |
| Heroic | Hestia | Population and ranged soldiers |
| Mythic | Hera | Myrmidons and myth units |
| Mythic | Hephaestus | Armory and unique units |
| Mythic | Artemis | Heroes and ranged soldiers |
| Mythic | Persephone | Infantry |

| Major god | Classical | Heroic | Mythic |
|---|---|---|---|
| Zeus | Athena | Apollo | Hephaestus |
| Poseidon | Ares | Aphrodite | Hephaestus |
| Hades | Athena | Aphrodite | Hephaestus |
| Demeter | Pan | Hestia | Hera |

**Matchups.** Hephaestus is the default Mythic pick because armory upgrades lift the whole
army — the best fit for a slow, upgrade-driven push. Hera (Myrmidons) beats Hephaestus only
when we are already ahead and want a decisive infantry spike. Athena over Ares when
available: Hoplite upgrades plus Restoration (a defensive god power) suit holding ground.
Aphrodite is the economy pick when the alternative is a combat god we do not need yet; Pan
is the only genuine defence Classical god. Apollo beats Dionysus when the enemy leans
melee (ranged + vision), Dionysus when we expect a long grind (unit health).

## Egyptians

| Age | God | Focus |
|---|---|---|
| Classical | Bast | Laborers |
| Classical | Ptah | Technology |
| Classical | Anubis | Anubites and Monuments |
| Heroic | Sobek | Buildings and camel units |
| Heroic | Sekhmet | Ranged and siege weapons |
| Heroic | Nephthys | Pharaohs and Priests |
| Mythic | Osiris | Camel Riders and Pharaohs |
| Mythic | Horus | Infantry |
| Mythic | Thoth | Laborers and War Elephants |

| Major god | Classical | Heroic | Mythic |
|---|---|---|---|
| Ra | Bast | Sekhmet | Horus |
| Isis | Bast | Nephthys | Thoth |
| Set | Ptah | Sekhmet | Horus |

**Matchups.** Egyptians generate favour from Monuments, so economy picks compound. Bast
(labourers) is the Classical default — the villager boost is exactly our style. Sekhmet
(ranged + siege) is the Heroic pick: it answers both massed infantry and turtling, which
is what a slow push struggles with. Nephthys (Pharaohs + Priests) is the defensive
alternative, giving heroes and healing for holding. Horus (infantry) is the Mythic
default; Thoth (elephants + labourers) when the enemy is cavalry-heavy.

## Norse

| Age | God | Focus |
|---|---|---|
| Classical | Freyja | Cavalry and heroes |
| Classical | Forseti | Infantry |
| Classical | Heimdall | Buildings |
| Classical | Ullr | Longhouse units and defences |
| Heroic | Skadi | Economy and Throwing Axemen |
| Heroic | Bragi | Myth units and earning Favour |
| Heroic | Njord | Cavalry |
| Heroic | Aegir | Heroes and siege weapons |
| Mythic | Baldr | Cavalry and siege weapons |
| Mythic | Tyr | Infantry |
| Mythic | Hel | Myth units |
| Mythic | Vidar | Human soldiers and heroes |

| Major god | Classical | Heroic | Mythic |
|---|---|---|---|
| Thor | Forseti | Skadi | Tyr |
| Odin | Heimdall | Skadi | Tyr |
| Loki | Heimdall | Bragi | Tyr |
| Freyr | Ullr | Aegir | Vidar |

**Matchups.** Heimdall (buildings) and Ullr (defences) are the defence picks and are
preferred over the cavalry/hero options when available. Skadi is the standout Heroic pick:
economy plus Throwing Axemen covers both halves of our style. Tyr (infantry) is the Mythic
default; Vidar (human soldiers + heroes) when Freyr is the major god and we want hero
support; Baldr only if we expect to need siege.

## Atlanteans

| Age | God | Focus |
|---|---|---|
| Classical | Prometheus | Hero creation |
| Classical | Leto | Automatons |
| Classical | Oceanus | Infantry |
| Heroic | Hyperion | Heroes |
| Heroic | Rheia | Favour and infantry |
| Heroic | Theia | Cavalry |
| Mythic | Helios | Siege weapons |
| Mythic | Atlas | Infantry |
| Mythic | Hekate | Myth units |

| Major god | Classical | Heroic | Mythic |
|---|---|---|---|
| Kronos | Prometheus | Rheia | Atlas |
| Oranos | Oceanus | Hyperion | Hekate |
| Gaia | Oceanus | Rheia | Atlas |

**Matchups.** Atlantean favour comes from Oracles and Town Centers, so anything that keeps
us alive and expanding compounds. Prometheus (hero creation) is a strong defensive pick
against myth-heavy enemies. Oceanus (infantry) is the safe all-round Classical choice.
Rheia (favour + infantry) is the economy pick in Heroic; Hyperion (heroes) when we expect
enemy myth units. Atlas (infantry) is the Mythic default; Hekate (myth units) when we want
a defensive wall of myth.

## Chinese

| Age | God | Focus |
|---|---|---|
| Classical | Xuannü | Healing and army production |
| Classical | Chiyou | Military and looting |
| Classical | Houtu | Economy and defence |
| Heroic | Goumang | Cavalry and wood gathering |
| Heroic | Nüba | Myth units and ranged soldiers |
| Heroic | Rushou | Infantry and trade |
| Mythic | Gonggong | Heroes and cavalry |
| Mythic | Huangdi | Human soldiers |
| Mythic | Zhurong | Myth units and farming |

| Major god | Classical | Heroic | Mythic |
|---|---|---|---|
| Fuxi | Xuannü | Nüba | Huangdi |
| Nüwa | Houtu | Rushou | Zhurong |
| Shennong | Houtu | Rushou | Huangdi |

**Matchups.** Houtu (economy + defence) is the ideal Classical pick for us and is taken
wherever it is available. Xuannü (healing + army production) is the alternative — sustain
instead of raw economy. Nüba (myth + ranged) answers melee pushes; Rushou (infantry +
trade) is the economy/safe pick. Huangdi (human soldiers) is the Mythic default; Zhurong
(myth + farming) when we want economy to keep flowing into a long game.

## Japanese

| Age | God | Focus |
|---|---|---|
| Classical | Ame-no-Uzume | Mikos and infantry |
| Classical | Minakatatomi | Hunting and ranged soldiers |
| Classical | Inari Ōkami | Cavalry and myth units |
| Heroic | Hachiman | Archers and heroes |
| Heroic | Fūjin | Cavalry and myth units |
| Heroic | Raijin | Infantry and god powers |
| Mythic | Takemikazuchi | Samurai and infantry |
| Mythic | Watatsumi | Shinobi and Yumi Horse Archers |
| Mythic | Ōkuninushi | Buildings and siege |

| Major god | Classical | Heroic | Mythic |
|---|---|---|---|
| Amaterasu | Ame-no-Uzume | Hachiman | Takemikazuchi |
| Tsukuyomi | Ame-no-Uzume | Hachiman | Ōkuninushi |
| Susanoo | Minakatatomi | Raijin | Takemikazuchi |

**Matchups.** Ame-no-Uzume (Mikos = favour economy, plus infantry) is the Classical
default; Minakatatomi (hunting + ranged) when we are on a hunting-heavy map. Hachiman
(archers + heroes) is the defensive Heroic pick and answers enemy myth units; Raijin
(infantry + god powers) when we want offensive tempo. Takemikazuchi (samurai + infantry)
is the Mythic default; Ōkuninushi (buildings + siege) when the enemy turtles.

## Aztecs

| Age | God | Focus |
|---|---|---|
| Classical | Patecatl | Settlers and healing |
| Classical | Malinalxochitl | Poison and curses |
| Classical | Huehuecóyotl | Traps and stealth |
| Heroic | Coatlicue | Buildings and siege |
| Heroic | Coyolxauhqui | Devotion and upgrades |
| Heroic | Itzpapalotl | Tonalli and Noble Hut soldiers |
| Mythic | Tlaloc | Economy and Great Temples |
| Mythic | Mictlantecuhtli | Warrior Priests and death |
| Mythic | Xolotl | Myth units |

| Major god | Classical | Heroic | Mythic |
|---|---|---|---|
| Huitzilopochtli | Patecatl | Coatlicue | Tlaloc |
| Tezcatlipoca | Huehuecóyotl | Coyolxauhqui | Xolotl |
| Quetzalcoatl | Patecatl | Coatlicue | Tlaloc |

**Matchups.** Patecatl (settlers + healing) is the Classical economy pick and Aztec
settlers are strong, so it compounds. Huehuecóyotl (traps + stealth) is the defensive
alternative. Coatlicue (buildings + siege) is the Heroic pick for a slow push; Coyolxauhqui
(devotion + upgrades) when we want the upgrade path. Tlaloc (economy + Great Temples) is
the Mythic default; Xolotl (myth units) when we want defensive myth.

## Changing these

The picks live in `godApplyMinorGods()` in `god_bot.xs`, one `case` per major god.
They are a first pass based on each god's documented focus, **not** on measured results —
revisit them once the telemetry in [`god-bot-design.md`](god-bot-design.md) shows
which games are actually being lost and why.
