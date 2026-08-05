
const MAP_LIST_VISIBLE_ROWS = 17
const MAP_LIST_SCROLL_SPEED = 0

function main()
{
	Globalize( InitMapsMenu )
	Globalize( OnOpenMapsMenu )
	Globalize( OnCloseMapsMenu )

	RegisterSignal( "OnCloseMapsMenu" )
}

function InitMapsMenu()
{
	file.menu <- GetMenu( "MapsMenu" )
	local menu = file.menu

	AddEventHandlerToButtonClass( menu, "MapButtonClass", UIE_GET_FOCUS, Bind( MapButton_Focused ) )
	AddEventHandlerToButtonClass( menu, "MapButtonClass", UIE_LOSE_FOCUS, Bind( MapButton_LostFocus ) )
	AddEventHandlerToButtonClass( menu, "MapButtonClass", UIE_CLICK, Bind( MapButton_Activate ) )
	AddEventHandlerToButtonClass( menu, "MapListScrollUpClass", UIE_CLICK, Bind( OnMapListScrollUp_Activate ) )
	AddEventHandlerToButtonClass( menu, "MapListScrollDownClass", UIE_CLICK, Bind( OnMapListScrollDown_Activate ) )

	file.starsLabel <- menu.GetChild( "StarsLabel" )
	file.star1 <- menu.GetChild( "MapStar0" )
	file.star2 <- menu.GetChild( "MapStar1" )
	file.star3 <- menu.GetChild( "MapStar2" )

	file.buttons <- GetElementsByClassname( menu, "MapButtonClass" )
	foreach ( button in file.buttons )
		button.s.dlcGroup <- null

	file.numMapButtonsOffScreen <- null
	file.mapListScrollState <- 0
}

function OnOpenMapsMenu()
{
	local buttons = file.buttons
	local mapsArray = GetPrivateMatchMaps()

	file.numMapButtonsOffScreen = mapsArray.len() - MAP_LIST_VISIBLE_ROWS
	Assert( file.numMapButtonsOffScreen >= 0 )

	foreach ( button in buttons )
	{
		local buttonID = button.GetScriptID().tointeger()

		if ( buttonID >= 0 && buttonID < GetPrivateMatchMaps().len() )
		{
			if (GetModeNameForEnum(level.ui.privatematch_mode) == "campaign_carousel") {
				button.SetText( GetCampaignMapDisplayName( mapsArray[buttonID] ) )
			} else {
				button.SetText( GetMapDisplayName( mapsArray[buttonID] ) )
			}

			button.SetEnabled( true )
			button.s.dlcGroup = GetDLCMapGroupForMap( mapsArray[buttonID] )
		}
		else
		{
			button.SetText( "" )
			button.SetEnabled( false )
		}

		if ( buttonID == level.ui.privatematch_map && buttonID < GetPrivateMatchMaps().len() )
		{
			printt( buttonID, mapsArray[buttonID] )
			button.SetFocused()
		}
	}

	file.starsLabel.Hide()
	file.star1.Hide()
	file.star2.Hide()
	file.star3.Hide()

	RegisterButtonPressedCallback( MOUSE_WHEEL_UP, OnMapListScrollUp_Activate )
	RegisterButtonPressedCallback( MOUSE_WHEEL_DOWN, OnMapListScrollDown_Activate )

	UpdateDLCMapButtons()

	thread MonitorDLCAvailability()
}

function UpdateDLCMapButtons()
{
	local buttons = file.buttons

	foreach ( button in buttons )
	{
		if ( button.s.dlcGroup == null || button.s.dlcGroup < 1 )
			continue

		if ( ServerHasDLCMapGroupEnabled( button.s.dlcGroup ) )
			button.SetLocked( false )
		else
			button.SetLocked( true )

		if ( button.IsFocused() )
			UpdateMapButtonTooltip( button )
	}
}

function UpdateMapButtonTooltip( button )
{
	local menu = file.menu

	if ( button.s.dlcGroup > 0 )
	{
		if ( !IsDLCMapGroupEnabledForLocalPlayer( button.s.dlcGroup ) )
			HandleLockedCustomMenuItem( menu, button, ["#DLC_REQUIRED"] )
		else if ( !ServerHasDLCMapGroupEnabled( button.s.dlcGroup ) )
			HandleLockedCustomMenuItem( menu, button, ["#NOT_OWNED_BY_ALL_PLAYERS"] )
		else
			HandleLockedCustomMenuItem( menu, button, [], true )
	}
}

function OnCloseMapsMenu()
{
	DeregisterButtonPressedCallback( MOUSE_WHEEL_UP, OnMapListScrollUp_Activate )
	DeregisterButtonPressedCallback( MOUSE_WHEEL_DOWN, OnMapListScrollDown_Activate )

	Signal( uiGlobal.signalDummy, "OnCloseMapsMenu" )
}

function MapButton_Focused( button )
{
	local buttonID = button.GetScriptID().tointeger()

	local menu = file.menu
	local nextMapImage = menu.GetChild( "NextMapImage" )
	local nextMapName = menu.GetChild( "NextMapName" )
	local nextMapDesc = menu.GetChild( "NextMapDesc" )

	// White text for readability
	nextMapName.SetColor( 255, 255, 255 )
	nextMapDesc.SetColor( 255, 255, 255 )

	local mapsArray = GetPrivateMatchMaps()
	local mapName = mapsArray[buttonID]

	local mapImage
	if ( mapName == "mp_mia" || mapName == "mp_nest2" || mapName == "mp_box" || mapName == "mp_npe" )
		mapImage = "../loadscreens/" + mapName + "_widescreen"
	else
		mapImage = "../ui/menu/lobby/lobby_image_" + mapName

	nextMapImage.SetImage( mapImage )
	nextMapImage.SetColor( 165, 165, 165 )
	
	if (GetModeNameForEnum(level.ui.privatematch_mode) == "campaign_carousel") {
		nextMapName.SetText( GetCampaignMapDisplayName( mapName ) )
		nextMapImage.SetColor( 150, 150, 150 )
		local campaignDescriptions = {
			mp_fracture =    "1750 Hours, July 15, 2710\n————————————\nThe 1st Militia Fleet arrives in orbit around Victor, desperately low on fuel. They've embedded themselves within a civilian trading convoy, as to not trigger the IMC's orbital defense array. Bish had warned them that a raid of this scale was a very bad idea. They'll either get the fuel or die trying."
			mp_colony =      "1604 Hours, July 20, 2710\n————————————\nTroy is a backwater world, even by Frontier standards. Initially arriving in search of Militia fugitives, IMC recon satellites found something far worse. Sergeant Blisk has ordered that MK II Spectres be deployed to help. But in trying to reclaim the Vice Admiral's lost ship, an old war hero is forced out of hiding..."
			mp_relic =       "1800 Hours, July 20, 2710\n————————————\nHaving lost his wife in the massacre, MacAllan makes a deal with the Militia. Their mission is to get the surviving colonists out of harm's way. In exchange, they will receive the Odyssey's black box. If MacAllan is to be believed, it may hold the key to defeating the IMC."
			mp_angel_city =  "1530 Hours, August 2, 2710\n—————————————\nAfter some digging, Bish has found the next part of MacAllan's plan: an air traffic controller in Angel City's harbor district. MacAllan says this old friend of his can fly anything. But the IMC's Spyglass Network is everywhere. Getting in is the easy part. Getting out will be... less so."
			mp_outpost_207 = "0105 Hours, August 4, 2710\n—————————————\nMacAllan's gambit during the Battle of Angel City paid off - or so it seems. The IMS Sentinel retreats to the drydock, guarded by Outpost 207. Following the advice of Barker, the Militia sends in a surgical strike team to take out the ship, with the Vice Admiral still onbaord."
			mp_boneyard =    "1311 Hours, August 12, 2710\n——————————————\nAgainst his will, Barker takes the Militia to the Badlands System, the site of an abandoned IMC research facility. Allegedly, it used ultrasonic weapons to repel hostile wildlife. Bish's job is to collect data and learn how to destroy other towers like it before the IMC can scuttle the base."
			mp_airbase =     "0506 Hours, August 29, 2710\n——————————————\nAt the eleventh hour, IMC reinforcements prepare to lift off from Despoina, the fourth moon of Demeter. While the Militia commits to a frontal assault, Commander Sarah Briggs leads a strike team inside the base, now armed with Bish's tower-crippling virus - a program he calls the 'Icepick.'"
			mp_o2 =          "0700 Hours, August 29, 2710\n——————————————\nThe 1st Militia Fleet launches its final assault on the gate-world of Demeter, with the goal of severing the link between the Frontier and the Core Systems. While Bish leads a cyber-attack against the Spyglass Network, MacAllan and Vice Admiral Graves play out their long-awaited endgame..."
			mp_corporate =   "1530 Hours, December 5, 2710\n——————————————\nIn the epilogue of Demeter's destruction, Marcus Graves was court-martialed for lying under oath about the Odyssey. But after being rescued from a Colonial Navy black site, he now forms an uneasy alliance with the Militia. Together, they attempt to strike one of the IMC's Spectre facilities."
		}

		if ( mapName in campaignDescriptions ) {
			nextMapDesc.SetText( campaignDescriptions[mapName] )
		} else {
			nextMapDesc.SetText( "#" + mapName + "_CAMPAIGN_MENU_DESC" )
		}
	}
	else
	{
		nextMapName.SetText( GetMapDisplayName( mapName ) )

		// --- CUSTOM MAP DESCRIPTION OVERRIDES ---
		local customDescriptions = {
			mp_mia = "A group of IMC and Militia forces make their last stand on the outskirts of Demeter. Neither were informed that the operation has already failed and that rescue isn't coming...",
			mp_nest2 = "Following a massive data breach, IMC operatives must infiltrate one of their own facilities to destroy critical information related to Project TYPHON.",
			mp_fracture = "Years of aggressive fuel extracting have taken their toll on this former colony for the privileged in the Yuma System. It has since been abandoned, with entire continents being turned upside down.",
			mp_nexus = "IMC forces preform a routine search at a backwater agricultural outpost that is suspected of harboring Militia personnel. Unbeknownst to them, this planet is the Frontier Militia's current base of operations.",
			mp_overlook = "This armament facility has been repurposed by the IMC into a makeshift penitentiary for prisoners of war. The Militia attempt to rescue a whistleblower that is being held in maximum security.",
			mp_o2 = "Demeter is a critical fueling station for IMC forces making the jump to the Frontier. Bombarded by solar winds from a dying red giant, it is the gateway between the Frontier and the Core Systems.",
			mp_outpost_207 = "Orbital defense cannons are stationed at high altitude to fend off against incursions from hostile capital ships. This outpost is responsible defending an IMC shipyard in the Freeport system.",
			mp_airbase = "IMC Airbase Sierra is defended against local wildlife by the latest generation of repulsor towers. Set on the fourth moon of the planet Demeter, it is the single largest airfield in the Frontier.",
			mp_relic = "Parts salvaged from this old IMC shipwreck are sent into the valley below for further processing. Years ago, this Andromeda-class carrier was reported missing after a mutiny happened onboard.",
			mp_colony = "IMC and Militia forces clash in the close-quarters of an uncharted rural colony, built from the scrapped parts of the ghost ship, IMS Odyssey. It was abandoned after a massacre was committed by IMC Spectres.",
			mp_angel_city = "Angel City is one of the largest human settlements on the Froniter. When the IMC instituted martial law, massive walls were built to divide the city into smaller districts. It has recently entered the tenth year of its temporary 'two-week' lockdown.",
			mp_smugglers_cove = "Part arms bazaar and part pirate enclave, Smuggler's Cove is famous for its selection of mercenaries and black-market kits. Visitors are searched by the 'welcoming committee' before being taken to the mainland.",
			mp_wargames = "Pilot Certification Simulators are networked together for multi-Pilot training sessions. Using data gathered from previous defeats, this advanced IMC program seeks to push Pilots even further.",
			mp_rise = "Militia special forces set up a Long-Range Desert Patrol outpost in an abandoned IMC reservoir, not far from Training Ground Whitehead. This planet, known as Gridiron, is a hostile world, baked by solar radiation.",
			mp_boneyard = "Extensive research on wildlife repulsor technology was conducted at this IMC facility, many years ago. Its existence has since been purged from all written records.",
			mp_training_ground = "With 'Only the strong survive' as its slogan, this Pilot training regiment claims to have a 98 percent fatality rate - but that assumes their numbers are to be trusted. The IMC are well known for their propaganda.",
			mp_haven = "This luxury retreat for the wealthy was built on the edge of a massive crater lake. Many of its frequenters have stocks in defense contracting, and are very interested in seeing the Frontier's war continue.",
			mp_swampland = "Drainage operations have revealed ancient ruins of unknown origin. Vice Admiral Spyglass dispatches a team to investigate, at the request of the IMC's secretive Archeological Research Division...",
			mp_runoff = "Once owned by a neutral terraforming company, the IMC has forcefully taken this water treatment facility. This world has been chosen as the new Fleet Operations Base for the IMC Navy following the Battle of Demeter.",
			mp_harmony_mines = "Energy-rich ores are extracted at this mining facility owned by Kodai Industries on the planet Harmony. Lithium, cobalt, and tungsten carbide are instrumental for the Frontier's war machine.",
			mp_corporate = "Applied Robotics labs on the Frontier, such as this one, developed the first automated infantry 'Spectre' units. Hammond Robotics is an IMC Premier Technology Company, though many secrets are hidden under NDAs.",
			mp_lagoon = "An IMC carrier makes an emergency landing on a small fishing village in the Freeport system, though it is unlikely they're here to ask the locals for directions.",
			mp_backwater = "High in the mountains, ex-IMC pilot Barker and his fellow colonists have made a comfortable living by producing moonshine in this hidden bootlegging colony. It brings back memories of simpler times before the war.",
			mp_switchback = "Situated near a Kodai mining facility, this mountainside settlement is crucial for transporting goods and materials. It harkens back to the Gold Rush-era boomtowns of centuries prior.",
			mp_zone_18 = "Hidden in the vast wilderness of the Dakota System, an abandoned IMC research facility has been reactivated after the destruction of Hammond Robotics' corporate HQ. Intel suggests a new Spectre model is being developed here."
			mp_sandtrap = "Beyond the Frontier's established shipping lanes, this facility holds deep reservoirs of unrefined fuel. This fuel contains a negative energy density that satisfies the Einstein-Alcubierre metric, allowing for faster-than-light travel.",
			mp_box = "Hammond Robotics' Asset Testing Environment is used for simulating weapons and equipment that are still in their early development phase.",
			mp_npe = "Simulation Training Pods are used for Pilot certification exams, though many have been cracked and distributed by criminal networks. Remember, piracy is a crime."
		}

		if ( mapName in customDescriptions ) {
			nextMapDesc.SetText( customDescriptions[mapName] )
		} else {
			nextMapDesc.SetText( GetMapDisplayDesc( mapName ) )
		}
	}
	if ( !IsPrivateMatch() )
	{
		file.starsLabel.Show()
		UpdateSelectedMapStarData( menu, mapName, "coop" )
	}

	// Update window scrolling if we highlight a map not in view
	local minScrollState = clamp( buttonID - (MAP_LIST_VISIBLE_ROWS - 1), 0, file.numMapButtonsOffScreen )
	local maxScrollState = clamp( buttonID, 0, file.numMapButtonsOffScreen )

	if ( file.mapListScrollState < minScrollState )
		file.mapListScrollState = minScrollState
	if ( file.mapListScrollState > maxScrollState )
		file.mapListScrollState = maxScrollState

	UpdateMapListScroll()
	delaythread( 0.02 ) UpdateMapButtonTooltip( button ) // Hacky delay needed or tooltip position will use the button position prior to scroll offset
}

function MapButton_LostFocus( button )
{
	HandleLockedCustomMenuItem( file.menu, button, [], true )
}

function MapButton_Activate( button )
{
	if ( button.IsLocked() )
	{
		if ( !IsDLCMapGroupEnabledForLocalPlayer( button.s.dlcGroup ) )
			ShowDLCStore()

		return
	}

	local mapsArray = GetPrivateMatchMaps()
	local mapID = button.GetScriptID().tointeger()
	local mapName = mapsArray[mapID]

	printt( mapName, mapID )

	SetCoopCreateAMatchMapname( mapName )

	ClientCommand( "SetCustomMap " + mapName )
	CloseTopMenu()
}

function MonitorDLCAvailability()
{
	EndSignal( uiGlobal.signalDummy, "OnCloseMapsMenu" )

	local available = [ null, null, null ]
	local lastAvailable = clone available
	local doUpdate

	while ( 1 )
	{
		doUpdate = false

		for ( local i = 0; i < 3; i++ )
		{
			available[i] = ServerHasDLCMapGroupEnabled( i + 1 ) // 1-3

			if ( available[i] != lastAvailable[i] )
			{
				lastAvailable[i] = available[i]
				doUpdate = true
			}
		}

		if ( doUpdate )
			UpdateDLCMapButtons()

		WaitFrameOrUntilLevelLoaded()
	}
}

function GetPrivateMatchMaps()
{
	if (GetModeNameForEnum(level.ui.privatematch_mode) == "campaign_carousel") {
		local campaignMaps = ["mp_fracture","mp_colony","mp_relic","mp_angel_city","mp_outpost_207","mp_boneyard","mp_airbase","mp_o2","mp_corporate"]
		return campaignMaps
	}
	local mapsArray = []
	mapsArray.resize( getconsttable().ePrivateMatchMaps.len() )

	foreach ( k, v in getconsttable().ePrivateMatchMaps )
		mapsArray[v] = k

	return mapsArray
}

function OnMapListScrollUp_Activate(...)
{
	if( GetModeNameForEnum( level.ui.privatematch_mode ) == "campaign_carousel" )
		return

	file.mapListScrollState--
	if ( file.mapListScrollState < 0 )
		file.mapListScrollState = 0

	UpdateMapListScroll()
}

function OnMapListScrollDown_Activate(...)
{
	if( GetModeNameForEnum( level.ui.privatematch_mode ) == "campaign_carousel" )
		return

	file.mapListScrollState++
	if ( file.mapListScrollState > file.numMapButtonsOffScreen )
		file.mapListScrollState = file.numMapButtonsOffScreen

	UpdateMapListScroll()
}

function UpdateMapListScroll()
{
	local buttons = file.buttons
	local basePos = buttons[0].GetBasePos()
	local offset = buttons[0].GetHeight() * file.mapListScrollState

	buttons[0].SetPos( basePos[0], basePos[1] - offset )
}