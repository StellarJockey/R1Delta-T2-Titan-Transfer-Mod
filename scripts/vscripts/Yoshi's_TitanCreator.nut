
const DMG_COR_IMG = "../ui/menu/items/ability_images/chassis_page_core_atlas"
const DAS_COR_IMG = "../ui/menu/items/ability_images/chassis_page_core_stryder"
const SHI_COR_IMG = "../ui/menu/items/ability_images/chassis_page_core_ogre"

const DMG_COR_NAM = "#CHASSIS_ATLAS_CORE_NAME"
const DMG_COR_DES = "#CHASSIS_ATLAS_CORE_DESCRIPTION"
const DAS_COR_NAM = "#CHASSIS_STRYDER_CORE_NAME"
const DAS_COR_DES = "#CHASSIS_STRYDER_CORE_DESCRIPTION"
const SHI_COR_NAM = "#CHASSIS_OGRE_CORE_NAME"
const SHI_COR_DES = "#CHASSIS_OGRE_CORE_DESCRIPTION"

const ATLAS_IMG_IMC = "../ui/menu/loadouts/titan_chassis_atlas_imc"
const ATLAS_IMG_MCO = "../ui/menu/loadouts/titan_chassis_atlas_mcor"
const STRYDER_IMG_IMC = "../ui/menu/loadouts/titan_chassis_stryder_imc"
const STRYDER_IMG_MCO = "../ui/menu/loadouts/titan_chassis_stryder_mcor"
const OGRE_IMG_IMC = "../ui/menu/loadouts/titan_chassis_ogre_imc"
const OGRE_IMG_MCO = "../ui/menu/loadouts/titan_chassis_ogre_mcor"

//PrecacheMaterial( "models/titans/ogre/t_h_scorch_warpaint_skin01" )
/*
Instructions:

name = the titan name, example: "titan_atlas"
type = the titan type, example: "stryder", for this mod please use "special_stryder", "special_atlas", or "special_ogre"
unless you need it specific.
//embark override is purely for _titan_embark script.

Rest is pretty self-explanatory really, its in the name of the variables.

Now remember to import SET file in classes and add to the enum in 

*/
function main()
{
	Globalize( setUp )
	//Globalize( BlackMarketTitan_Construct )
}

function setUp( script_int )//I shoulda had this as a bool but eh
{
	::BlackMarketTitans <- {}
	::TitanNames <- []

	local is_item = false

	if( script_int == 1 )
	{
		//IncludeFile( "_items" )
	}
	else
	{
		IncludeFile( "_items" )
		is_item = true
	}
	//IncludeFile( "_anim_aliases" )
	//IncludeFile( "_titan_soul" )
	//IncludeScript( "_titan_embark" )
	printl( "BlackMarketScript is ACTIVE" )//finally show what my BMT mod is really for -YoshitheHut

	//BlackMarketTitan_Construct( is_item, "titan_ion", "special_atlas", "titan_atlas", 50, "Black Market Atlas", "Modified Atlas with a focus on the balance between speed and armor.", ATLAS_IMG_IMC, ATLAS_IMG_MCO, DAS_COR_NAM, DAS_COR_DES, DAS_COR_IMG, 85, 90, 76, 2 )
	BlackMarketTitan_Construct( is_item, "titan_legion", "special_ogre", "titan_ogre", 50, "Legion", "Ultra-Heavy Ogre classed titan with slow speed and heavy armor.", OGRE_IMG_IMC, OGRE_IMG_MCO, "Core Ability: Bullet Storm", "Gives you a high-capacity, high-firerate XO-16 for it's duration", "../ui/menu/items/mod_icons/scatterfire", 30, 40, 100, 1 )
	BlackMarketTitan_Construct( is_item, "titan_scorch", "special_ogre", "titan_ogre", 50, "Scorch", "Ultra-Heavy Ogre classed titan with slow speed and heavy armor.", OGRE_IMG_IMC, OGRE_IMG_MCO, "Core Ability: Ordnance Core", "Routes reserve power into your ordnance system, drastically decreasing it's recharge time.", "../ui/menu/items/mod_icons/rapid_fire_missiles", 30, 40, 100, 1 )
	BlackMarketTitan_Construct( is_item, "titan_ion", "special_atlas", "titan_atlas", 50, "Ion", "A successor to the Atlas that uses a second tactical based on it's loadout, but does not use ordnance.", ATLAS_IMG_IMC, ATLAS_IMG_MCO, "Core Ability: Piercer Cannon", "Deploys a variant of the Charge Cannon built to charge to a higher capacity.", "../ui/menu/items/mod_icons/instant_shot", 85, 90, 76, 2 )
	//BlackMarketTitan_Construct( is_item, "titan_tone", "special_atlas", "titan_atlas", 50, "Tone", "atlas desc.", ATLAS_IMG_IMC, ATLAS_IMG_MCO, DMG_COR_NAM, DMG_COR_DES, DMG_COR_IMG, 85, 90, 76, 2 )
	BlackMarketTitan_Construct( is_item, "titan_northstar", "special_stryder", "titan_stryder", 50, "Northstar", "Ultra-Light Stryder classed titan capable of flight via it's tactical system.", STRYDER_IMG_IMC, STRYDER_IMG_MCO, "Core Ability: Flight Core", "Allows easy flight and provides lock-on and salvo rockets for it's duration.", "../ui/menu/items/mod_icons/starburst", 100, 100, 25, 5 )
	BlackMarketTitan_Construct( is_item, "titan_ronin", "special_stryder", "titan_stryder", 50, "Ronin", "Ultra-Light Stryder classed titan with enhanced melee and boost capability.", STRYDER_IMG_IMC, STRYDER_IMG_MCO, "Core Ability: Ripper Shotgun", "Deploys an automatic variant of the WYS404 Shotgun with sprint-and-fire bracing.", "../ui/menu/items/passive_icons/run_and_gun", 100, 100, 25, 4 )
	//BlackMarketTitan_Construct( is_item, "titan_bm_stryder", "special_stryder", "titan_stryder", 50, "Black Market Stryder", "Modified Stryder with a focus on height advantage.", STRYDER_IMG_IMC, STRYDER_IMG_MCO, SHI_COR_NAM, SHI_COR_DES, SHI_COR_IMG, 95, 100, 57, 2 )
}//damn i forgor to check _pdef for my northstar

function BlackMarketTitan_Construct( is_item, name, type, embark_override, unlock_level, game_name, game_desc, titan_img_imc, titan_img_mcor, core_name, core_desc, core_img, statSpeed, statAccel, statHealth, statDash )
{
	if( is_item == true )
	{
		BlackMarket_ITEMCALL( name, unlock_level, game_name, game_desc, titan_img_imc, titan_img_mcor, core_name, core_desc, core_img, statSpeed, statAccel, statHealth, statDash )
	}
	else
	{
		TitanNames.append( name )
		//printl( TitanNames[0] )
		local TitanTable = {}
		TitanTable.name <- name
		TitanTable.type <- type
		TitanTable.emov <- embark_override
		BlackMarketTitans[ name ] <- TitanTable
	}
	//BlackMarket_ITEMCALL( name, unlock_level, game_name, game_desc, titan_img_imc, titan_img_mcor, core_name, core_desc, core_img, statSpeed, statAccel, statHealth, statDash )
	
	//BlackMarket_ACCESSTABLE( "titan_ion" )
}

main()
