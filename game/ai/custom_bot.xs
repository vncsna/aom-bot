//==============================================================================
// custom_bot.xs - Age of Mythology: Retold Custom AI Bot
//==============================================================================
include "core/main.xs";

//==============================================================================
/*	preInit()

	This function is called in main() before any of the normal initialization
	happens. Use it to override default values of variables as needed.
*/
//==============================================================================
void preInit()
{
	aiEcho("=== [CustomBot] preInit() started ===");
}

//==============================================================================
/*	postInit()

	This function is called in main() after the normal initialization is
	complete. Use it to override settings, build orders, or army plans.
*/
//==============================================================================
void postInit()
{
	aiEcho("=== [CustomBot] postInit() completed - Bot active! ===");
}
