//=========================================================
// MP ai functions for game modes
//
//=========================================================

RegisterSignal( "spotted_by_ai" )

const FRONTLINE_MIN_DIST_SQR		= 262144	// 512
const FRONTLINE_MAX_DIST_SQR		= 16777216	// 4096
const FRONTLINE_NPC_SPAWN_OFFSET	= 0			// min distance away from the frontline that a droppod will spawn.
const FRONTLINE_PLAYER_SPAWN_OFFSET	= 256		// min distance away from the frontline that a player will spawn.
const FRONTLINE_PLAYER_SPAWN_DIST	= 1536		// distance where the spawn score is at it's highest
const FRONTLINE_PLAYER_SPAWN_HEIGHT	= 320		//

const KPS_TIMEFRAME = 20.0			// timeframe in seconds to count death per second within.
const PLAYER_KPS_TIMEFRAME = 60.0	// timeframe in seconds to count death per second within. The goal is to kill 50% of the total player count per team
const FRONTLINE_MIN_TIME = 30.0
const NPC_KPS_LIMIT	= 10			// kills per KPS_TIMEFRAME to trigger a frontline change
const PLAYER_KPS_LIMIT = 0.75		// fraction of player count needed to be killed withing PLAYER_KPS_TIMEFRAME to trigger a frontline change

const MID_SPEC_MAX_AI_COUNT = 9		// max number of AI per side when playing on less then high-end machines (durango)
const MID_SPEC_PLAYER_CUTOFF = 8	// treat the server as high-end when the player count is less or equal to this.

// CTF AI support constants. Declared at file scope so SpawnFrontlineSquad can see CTF_DEBUG
// (const name resolution was failing when these were declared near the CTF functions at the bottom).
const CTF_FLAGRUN_GOAL_RADIUS      = 192		// how close the squad needs to get before re-evaluating (tightened from 256)
const CTF_FLAGRUN_REEVAL_PERIOD    = 1.5		// seconds between re-evaluating the objective mid-push (tightened from 3.0)
const CTF_FLAGRUN_ESCORT_RADIUS    = 128		// tight assault radius when escorting a player flag carrier -- grunts stick close
const CTF_DEBUG                    = true		// set false to silence diagnostic prints for release

// Fake-capture (grunt-delivered score) feature. Since NPCs cannot physically carry flags,
// we award a capture point when a friendly grunt reaches the enemy flag base. Heavily
// rate-limited to preserve match pacing and prevent grunts from winning the match outright.
const CTF_FAKECAP_ENABLED          = true		// master switch for scripted grunt captures
const CTF_FAKECAP_TRIGGER_DIST     = 150		// grunt must be this close to enemy flag base to trigger (bumped 96->150)
const CTF_FAKECAP_TEAM_COOLDOWN    = 40.0		// seconds between successive fake-captures by the same team (bumped 30->40 per user feedback)
const CTF_FAKECAP_MAX_PER_TEAM     = 6			// max fake-captures per team per match (single-player-vs-AI framing: grunts can potentially deliver a full win)
const CTF_FAKECAP_CHECK_PERIOD     = 0.5		// how often the fake-cap watchdog polls grunt positions (tightened 1.0->0.5)


function main()
{
	Globalize( SetupTeamDeathmatchNPCs )
	Globalize( Coop_OnPlayerOrNPCKilled )
	Globalize( SquadAssaultFrontline )
	Globalize( SquadAssault )
	Globalize( SquadHardpointRunThink )
	Globalize( GetHardpointObjectiveForTeam )
	Globalize( SquadFlagRunThink )
	Globalize( GetCTFFlagOriginForTeam )
	Globalize( GetCTFObjectiveForTeam )
	Globalize( CTFFakeCaptureWatchdog )
	Globalize( CTFFakeCaptureCheckTeam )
	Globalize( CTFAwardFakeCapture )
	Globalize( ShouldPrintFakeCapGateDiag )
	Globalize( SpawnFrontlineSquad )
	Globalize( TitanHasPilotInTitan )
	Globalize( CreateCopyOfPilotModel )

	Globalize( GetCurrentFrontline )
	Globalize( GetTeamCombatDir )
	Globalize( MoveFrontline )

	Globalize( GetFreeAISlots )
	Globalize( GetReservedAISquadSlots )
	Globalize( ReserveAISlots )
	Globalize( ReleaseAISlots )
	Globalize( FreeAISlotOnDeath )
	Globalize( ReserveSquadSlots )
	Globalize( ReleaseSquadSlots )

	Globalize( Spawn_TrackedGrunt )
	Globalize( Spawn_TrackedSpectre )
	PrecacheModel( "models/robots/agp/agp_hemlok_larger.mdl" )
	Minimap_PrecacheMaterial( "vgui/hud/cloak_drone_minimap_orange" )
	Minimap_PrecacheMaterial( "vgui/hud/cloak_drone_minimap" )

	Globalize( GetIndexSmallestSquad )
	Globalize( TryGetSmallestValidSquad )
	Globalize( SquadValidForClass )
	Globalize( GetReservedSquadSize )

	Globalize( SetFrontlineSides )
	Globalize( GetMaxAICount )
	Globalize( GetSpawnSquadSize )
	Globalize( SetLevelAICount )

	FlagInit( "FrontlineInitiated" )
	RegisterSignal( "FreeAISlotsUpdated" )
	RegisterSignal( "TitanHotDropComplete" )
	RegisterSignal( "DisableRocketPods" )
	RegisterSignal( "OnLostTarget" )
	RegisterSignal( "BubbleShieldStatusUpdate" )
	RegisterSignal( "FlagUpdate" )		// base-game CTF signal; defensively registered here in case our think starts before ctf.nut

	// Per-squad signals for SquadFlagRunThink. level.aiSquadCount is 3 by default; register
	// a safe upper bound of 8 per team to accommodate any future bump without code changes.
	for ( local i = 0; i < 8; i++ )
	{
		RegisterSignal( "SquadFlagRunThink_squad_imc" + i )
		RegisterSignal( "SquadFlagRunThink_squad_militia" + i )

		RegisterSignal( "SquadHardpointRunThink_squad_imc" + i )
		RegisterSignal( "SquadHardpointRunThink_squad_militia" + i )
	}

	level.max_npc_per_side <- 28
	level.max_npc_per_side_small <- 24

	level.occupiedAISlots <- {}
	level.occupiedAISlots[TEAM_IMC] <- 0
	level.occupiedAISlots[TEAM_MILITIA] <- 0
	level.levelAICount <- {}
	level.levelAICount[ TEAM_IMC ] <- level.max_npc_per_side
	level.levelAICount[ TEAM_MILITIA ] <- level.max_npc_per_side

	level.gameModeAICount <- {}
	level.gameModeAICount[ TEAM_IMC ] <- level.max_npc_per_side
	level.gameModeAICount[ TEAM_MILITIA ] <- level.max_npc_per_side

	level.midSpecAICount <- {}
	level.midSpecAICount[ TEAM_IMC ] <- level.max_npc_per_side
	level.midSpecAICount[ TEAM_MILITIA ] <- level.max_npc_per_side

	level.npcRespawnWait <- 10

	local npcPerSide = level.max_npc_per_side
	switch( GameRules.GetGameMode() )
	{
		case TITAN_BRAWL:
			npcPerSide = 0
			break
		case PILOT_SKIRMISH:
			npcPerSide = 0
			break
		case TEAM_DEATHMATCH:
			level.npcRespawnWait = 5
			break
		case ATTRITION:
			level.npcRespawnWait = 10
			break
		case LAST_TITAN_STANDING:
		case WINGMAN_LAST_TITAN_STANDING:
			level.npcRespawnWait = 5
			npcPerSide = GetCPULevelWrapper() == CPU_LEVEL_HIGHEND ? level.max_npc_per_side : 9
			break
		case CAPTURE_THE_FLAG:
			level.npcRespawnWait = 5
			npcPerSide = 18
			break
	}

	SetGameModeAICount( npcPerSide, TEAM_IMC )
	SetGameModeAICount( npcPerSide, TEAM_MILITIA )

	SetMidSpecAICount( MID_SPEC_MAX_AI_COUNT, TEAM_IMC )
	SetMidSpecAICount( MID_SPEC_MAX_AI_COUNT, TEAM_MILITIA )

	SetupLevelAICount()

	level.modifyAISlots <- {}
	level.modifyAISlots[TEAM_IMC] <- 0
	level.modifyAISlots[TEAM_MILITIA] <- 0

	level.reservedAISquadSlots <- {}
	level.dropship_team <- 0
	level.aiSquadCount <- 3
	level.aiSpawnCounter <- {}
	level.aiSpawnCounter[ TEAM_IMC ] <- 0
	level.aiSpawnCounter[ TEAM_MILITIA ] <- 0

	// debug stuff
	Globalize( DebugSendClientFrontline )
	Globalize( DebugSendClientFrontlineAllPlayers )
	Globalize( DebugSquad )
	Globalize( DebugNextFrontline )
	Globalize( DrawCurrentFrontline )
	Globalize( DebugDrawFrontLine )
	Globalize( DebugDrawFrontLineSpawn )
	Globalize( DrawMapCenter )
	Globalize( MoveBot )

	file.botIndex <-
	{
	 	[TEAM_IMC] = 0,
	 	[TEAM_MILITIA] = 0
	}

	RegisterSignal( "EndDebugSquadIndex" )

	const DEBUG_NPC_SPAWN			= 1
	const DEBUG_NPC_FRONTLINE		= 2
	const DEBUG_FRONTLINE_ENTS		= 4
	const DEBUG_KPS					= 8
	const DEBUG_ASSAULTPOINT		= 16
	const DEBUG_FRONTLINE_SELECTED	= 32
	const DEBUG_FRONTLINE_SWITCHED	= 64

	level.AssaultFunc <- null
	Globalize( ScriptedSquadAssault )

	file.debug <- 0
//	file.debug = DEBUG_FRONTLINE_SWITCHED
//	file.debug = DEBUG_NPC_SPAWN // + DEBUG_ASSAULTPOINT // + DEBUG_KPS // + DEBUG_FRONTLINE_SELECTED
	// end debug stuff
	file.pilotedtitans <- []
	file.pilots <- []
	file.pilotedtitanmodels <- {}
	file.spawnedtitans <- {}
	file.pilotmodels <- [
	"models/Humans/mcor_pilot/male_br/mcor_pilot_male_br.mdl",
	"models/Humans/mcor_pilot/male_cq/mcor_pilot_male_cq.mdl",
	"models/Humans/mcor_pilot/male_dm/mcor_pilot_male_dm.mdl",
	"models/Humans/imc_pilot/male_br/imc_pilot_male_br.mdl",
	"models/humans/imc_pilot/male_cq/imc_pilot_male_cq.mdl",
	"models/humans/imc_pilot/male_dm/imc_pilot_male_dm.mdl"
	]
	file.militiapilotmodels <- [
	"models/Humans/mcor_pilot/male_br/mcor_pilot_male_br.mdl",
	"models/Humans/mcor_pilot/male_cq/mcor_pilot_male_cq.mdl",
	"models/Humans/mcor_pilot/male_dm/mcor_pilot_male_dm.mdl"
	]
	file.imcpilotmodels <- [
	"models/Humans/imc_pilot/male_br/imc_pilot_male_br.mdl",
	"models/humans/imc_pilot/male_cq/imc_pilot_male_cq.mdl",
	"models/humans/imc_pilot/male_dm/imc_pilot_male_dm.mdl"
	]
	AddDamageByCallback( "npc_titan", Execution )
	AddDamageCallback( "npc_titan", NoPain )
	AddDamageCallback( "npc_soldier", NoPain )
	AddDamageCallback( "npc_titan", AutoTitan_NuclearPayload_DamageCallback )

	SpawnPoints_SetRatingMultipliers_Enemy( TD_AI, -2.0, -0.25, 0.0 )
	SpawnPoints_SetRatingMultipliers_Friendly( TD_AI, 0.5, 0.25, 0.0 )

	// DRONES
	local mode = GameRules.GetGameMode()
	if ( mode != COOPERATIVE && mode != TITAN_BRAWL && mode != LAST_TITAN_STANDING && mode != PILOT_SKIRMISH )
	{
		level.cloakedDronesManagedEntArrayID <- CreateScriptManagedEntArray()
		level.cloakedDroneClaimedSquadList <- {}
		Globalize( CloakedDroneIsSquadClaimed )
		Globalize( SpawnCloakDrone )
		RegisterSignal( "DroneCleanup" )
	}

	if ( mode == COOPERATIVE )
	{
		thread Coop_SpawnTitansAfterDelay()
	}
}

function Coop_OnPlayerOrNPCKilled( entity, attacker, damageInfo )
{
    return
}

function TitanHasPilotInTitan( titan )
{
	local pilotedtitans = []
	foreach( npc in file.pilotedtitans )
	if ( IsValid( npc ) && IsAlive( npc ) )
	    pilotedtitans.append( npc )
	file.pilotedtitans = pilotedtitans
	foreach( npc in pilotedtitans )
	    if ( npc == titan )
	        return true

	return false
}

function NPCIsPilot( pilot )
{
	local pilots = []
	foreach( npc in file.pilots )
	if ( IsValid( npc ) && IsAlive( npc ) )
	    pilots.append( npc )
	file.pilots = pilots
	foreach( npc in pilots )
	    if ( npc == pilot )
	        return true

	return false
}

function Execution( ent, damageInfo )
{
	local attacker = damageInfo.GetAttacker()
	if ( !ent.IsTitan() || damageInfo.GetDamageSourceIdentifier() != eDamageSourceId.titan_melee || !TitanHasPilotInTitan( attacker ) || !ent.GetDoomedState() || !CodeCallback_IsValidMeleeExecutionTarget( attacker, ent ) )
	    return

    damageInfo.SetDamage( 0 )
	thread PlayerTriesExecutionMelee( attacker, ent )
}

function NoPain( ent, damageInfo )
{
    // If it's a Titan without a pilot, allow standard damage processing
    if ( ent.IsTitan() && !TitanHasPilotInTitan( ent ) )
        return

    // If it's a Pilot NPC, ensure they can still take damage
    if ( !ent.IsTitan() && NPCIsPilot( ent ) )
    {
        damageInfo.AddDamageFlags( DAMAGEFLAG_NOPAIN ) // Optional: prevents flinching
        return // Exit here so damage isn't set to 0
    }

    // Default behavior for other NPCs
    damageInfo.AddDamageFlags( DAMAGEFLAG_NOPAIN )
}

function GiveTitanPilot( titan, trueorfalse )
{
	local pilotedtitans = []
	foreach( npc in file.pilotedtitans )
	if ( IsValid( npc ) && IsAlive( npc ) )
	pilotedtitans.append( npc )
	if ( !IsValid( titan ) || !IsAlive( titan ) )
	return
	if ( trueorfalse == true )
	pilotedtitans.append( titan )
	if ( trueorfalse == false )
	{
		local newpilotedtitans
		foreach( npc in pilotedtitans )
		if ( npc != titan )
		newpilotedtitans.append( titan )
		pilotedtitans = newpilotedtitans
	}
	file.pilotedtitans = pilotedtitans
}

function SetNPCAsPilot( pilot, trueorfalse )
{
	local pilots = []
	foreach( npc in file.pilots )
	if ( IsValid( npc ) && IsAlive( npc ) )
	pilots.append( npc )
	if ( !IsValid( pilot ) || !IsAlive( pilot ) )
	return
	if ( trueorfalse == true )
	pilots.append( pilot )
	if ( trueorfalse == false )
	{
		local newpilots
		foreach( npc in pilots )
		if ( npc != pilot )
		newpilots.append( pilot )
		pilots = newpilots
	}
	file.pilots = pilots
}

function CreateCopyOfPilotModel( titan )
{
	local model = Random( file.pilotmodels )
	if ( titan in file.pilotedtitanmodels )
	    model = file.pilotedtitanmodels[ titan ]
	local prop = CreatePropDynamic( model )
	prop.SetTeam( titan.GetTeam() )
	return prop
}

function GiveTitanPilotModel( titan, model )
{
	file.pilotedtitanmodels[ titan ] <- model
}

function NPCPilotEmbarkTitan( pilot, title, titan )
{
	pilot.EndSignal( "OnDestroy" )
	pilot.EndSignal( "OnDeath" )
	titan.EndSignal( "OnDestroy" )
	titan.EndSignal( "OnDeath" )
	local embarkSet = FindBestEmbark( pilot, titan )
	while( embarkSet == null )
	{
		wait 0.1
		embarkSet = FindBestEmbark( pilot, titan )
	}
	local animation = embarkSet.animSet.titanKneelingAnim
	local titanSubClass = GetSoulTitanType( titan.GetTitanSoul() )
	local Audio = GetAudioFromAlias( titanSubClass, embarkSet.audioSet.thirdPersonKneelingAudioAlias )
	local sequence = CreateFirstPersonSequence()
	sequence.attachment = "hijack"
	sequence.useAnimatedRefAttachment = embarkSet.action.useAnimatedRefAttachment
	sequence.thirdPersonAnim = GetAnimFromAlias( titanSubClass, embarkSet.animSet.thirdPersonKneelingAlias )
	// Never Used Because Game Has No Grapple
	/*
	if ( titan.GetTitanSoul().GetStance() > STANCE_STANDING )
	{
		sequence.thirdPersonAnim = GetAnimFromAlias( titanSubClass, embarkSet.animSet.thirdPersonStandingAlias )
	    animation = embarkSet.animSet.titanStandingAnim
		Audio = GetAudioFromAlias( titanSubClass, embarkSet.audioSet.thirdPersonStandingAudioAlias )
	}
	*/

	if ( IsCloaked( pilot ) )
		pilot.SetCloakDuration( 0, 0, 1.5 )

	pilot.SetInvulnerable()
	pilot.Anim_Stop()
	local pilotmodel = pilot.GetModelName()
	pilot.ClearInvulnerable()
	local newpilot
	
	if ( (pilot.ContextAction_IsActive() || pilot.ContextAction_IsBusy()) || pilot.IsInterruptable() )
	    thread FirstPersonSequence( sequence, pilot, titan )
    else
	{
	    newpilot = CreateEntity( "npc_soldier" )
	    DispatchSpawn( newpilot )
	    newpilot.SetOrigin( pilot.GetOrigin() )
	    newpilot.SetTeam( pilot.GetTeam() )
	    newpilot.SetModel( pilotmodel )
		GiveMinionWeapon( newpilot, "mp_weapon_rspn101" )
	    // newpilot.SetInvulnerable()  // Maybe this is the invincibility bug?
	    newpilot.SetTitle( title )
		pilot.Destroy()
		thread FirstPersonSequence( sequence, newpilot, titan )
	}
	EmitSoundOnEntity( titan, Audio )
	waitthread PlayAnimGravity( titan, animation )
	SetStanceStand( titan.GetTitanSoul() )
	GiveTitanPilot( titan, true )
	GiveTitanPilotModel( titan, pilotmodel )
	if ( IsValid( pilot ) )
	    pilot.Destroy()
	if ( IsValid( newpilot ) )
	    newpilot.Destroy()
}

function Spawn_PilotInDroppod( pilot, title, team, spawnPoint )
{
	local dropPod = CreatePropDynamic( DROPPOD_MODEL )
	InitFireteamDropPod( dropPod )

	local options = {}
	if ( IsValid( dropPod ) )
		dropPod.kv.VisibilityFlags = 0 

	// SAFETY: Hide the pilot and make them invulnerable while the pod is falling
	if ( IsValid( pilot ) )
	{
		pilot.kv.VisibilityFlags = 0
		pilot.SetInvulnerable()
	}

	waitthread LaunchAnimDropPod( dropPod, "pod_testpath", spawnPoint.GetOrigin(), spawnPoint.GetAngles(), options )
	PlayFX( "droppod_impact", spawnPoint.GetOrigin(), spawnPoint.GetAngles() )

	// Check validity again after the long wait
	if ( !IsValid( pilot ) )
	{
		if ( IsValid( dropPod ) )
			dropPod.kv.VisibilityFlags = 0
		return null
	}

	local newpilot = CreateEntity( "npc_soldier" )
	DispatchSpawn( newpilot )
	newpilot.SetOrigin( pilot.GetOrigin() )
	newpilot.SetTeam( pilot.GetTeam() )
	newpilot.SetModel( pilot.GetModelName() )
	newpilot.SetTitle( title )
	
	GiveMinionWeapon( newpilot, "mp_weapon_rspn101" )
	newpilot.SetMaxHealth( 200 )
	newpilot.SetHealth( 200 )
	newpilot.SetInvulnerable()
	local soldierEntities = [newpilot]
	ActivateFireteamDropPod( dropPod, null, soldierEntities )

	newpilot.WaittillAnimDone()

	if ( IsValid( newpilot ) )
    {
        newpilot.Hide()    
        newpilot.Anim_Stop()  // Stop any AI transition to running/combat
    }

    if ( IsValid( newpilot ) && IsAlive( newpilot ) )
    {
        if ( IsValid( pilot ) ) 
        {
            pilot.SetTitle( title )
            pilot.kv.VisibilityFlags = 7 // Show the pilot again
            // pilot.ClearInvulnerable()
            pilot.SetOrigin( newpilot.GetOrigin() )
            pilot.SetAngles( newpilot.GetAngles() )
        }
        newpilot.Destroy()
    }
    else
    {
        if ( IsValid( pilot ) )
            pilot.Destroy()
        return null
    }

    dropPod.kv.VisibilityFlags = 1
    return pilot
}

function TrackTitan( titan )
{
	local team = titan.GetTeam()
	while( IsValid( titan ) && IsAlive( titan ) )
	{
		team = titan.GetTeam()
		wait 0.1
	}
	file.spawnedtitans[team] <- file.spawnedtitans[team] - 1
}

function SetupLevelAICount()
{
	local aiCount = level.max_npc_per_side	// 12

	switch ( GetMapName() )
	{
		case "mp_airbase":
		case "mp_boneyard":
		case "mp_corporate":
		case "mp_nexus":
		case "mp_rise":
		case "mp_fracture":
		case "mp_o2":
		case "mp_training_ground":
		case "mp_swampland":
		case "mp_runoff":
		case "mp_wargames":
		case "mp_sandtrap":
		case "mp_harmony_mines":
		case "mp_haven":
		case "mp_nest2":
		case "mp_mia":
			break

		case "mp_angel_city":
		case "mp_lagoon":
		case "mp_outpost_207":
		case "mp_colony":
		case "mp_relic":
		case "mp_overlook":
		case "mp_smugglers_cove":
		case "mp_switchback":
		case "mp_zone_18":
		case "mp_backwater":
			aiCount = level.max_npc_per_side_small
			break

		case "mp_box":
			aiCount = 12
			break

		case "mp_npe":
			aiCount = 16
			break

	}

	SetLevelAICount( aiCount, TEAM_MILITIA )
	SetLevelAICount( aiCount, TEAM_IMC )
}

function GetMaxAICount( team )
{
	local AICount = min( level.levelAICount[ team ] , level.gameModeAICount[ team ]  )
	if ( GetCPULevelWrapper() != CPU_LEVEL_HIGHEND && !IsTrainingLevel() )
	{
		if ( Flag( "GamePlaying" ) && GameTime.PlayingTime() > START_SPAWN_GRACE_PERIOD )
		{
			// if we have fewer player lets use more AI
			if ( GetPlayerArray().len() > MID_SPEC_PLAYER_CUTOFF ) // fancy lerp action here
				AICount = min( AICount, level.midSpecAICount[ team ] )
		}
	}

	return AICount
}

function SetGameModeAICount( count, team )
{
	Assert( count <= level.max_npc_per_side, "Trying to set the AI count to more then max allowed (" + count + " vs 12)" )
	level.gameModeAICount[ team ] = count
}
Globalize( SetGameModeAICount )

function SetLevelAICount( count, team )
{
	Assert( count <= level.max_npc_per_side, "Trying to set the AI count to more then max allowed (" + count + " vs 12)" )
	level.levelAICount[ team ] = count
}

function SetMidSpecAICount( count, team )
{
	Assert( count <= level.max_npc_per_side, "Trying to set the AI count to more then max allowed (" + count + " vs 12)" )
	level.midSpecAICount[ team ] = count
}

function GetSpawnSquadSize( team )
{
	local maxAICount = GetMaxAICount( team )
	local squadSize = max( 1, floor( maxAICount / 3 ) )	// 3 is the number of squads we have per side.
	return min( squadSize, SQUAD_SIZE )	// never higher then SQUAD_SIZE, it's the max we can spawn with droppods
}

function ReleaseAISlots( team, count = 1 )
{
	level.occupiedAISlots[team] -= count
	level.ent.Signal( "FreeAISlotsUpdated" )
}

function ReserveAISlots( team, count = 1 )
{
	level.occupiedAISlots[team] += count
	level.ent.Signal( "FreeAISlotsUpdated" )
}

function GetFreeAISlots( team )
{
	local maxAICount = GetMaxAICount( team )
	local freeAISlots = maxAICount - level.occupiedAISlots[ team ]

	local modifyAISlots = 0

	if ( level.modifyAISlots[team] < 0 )
		modifyAISlots = min( abs( level.modifyAISlots[team] ), freeAISlots ) * -1
	else if ( level.modifyAISlots[team] > 0 )
		modifyAISlots = min( abs( level.modifyAISlots[team] ), freeAISlots )

	return freeAISlots + modifyAISlots
}

function ReleaseSquadSlots( squadName, count, npcClass )
{
	Assert( squadName in level.reservedAISquadSlots )
	Assert( count >= 1 )
	Assert( level.reservedAISquadSlots[ squadName ].npcClass == npcClass )

	level.reservedAISquadSlots[ squadName ].count -= count
	Assert( level.reservedAISquadSlots[ squadName ].count >= 0 )

	// remove classname when reserved slots are zero
	if ( level.reservedAISquadSlots[ squadName ].count == 0 )
		level.reservedAISquadSlots[ squadName ].npcClass = null
}

function ReserveSquadSlots( squadName, count, npcClass, team )
{
	if ( squadName == null )
		return

	if ( !( squadName in level.reservedAISquadSlots ) )
		level.reservedAISquadSlots[ squadName ] <- { count = 0, npcClass = null, team = team }

	local currentClass = level.reservedAISquadSlots[ squadName ].npcClass
	Assert( currentClass == null || currentClass == npcClass, "Can't reserve slot for npc of class " + npcClass + " in squad " + squadName + " because the NPC's classname doesn't match existing squad classname: " + currentClass )

	level.reservedAISquadSlots[ squadName ].count += count
	level.reservedAISquadSlots[ squadName ].npcClass = npcClass
}

function GetReservedAISquadSlots( squadName )
{
	if ( squadName in level.reservedAISquadSlots )
		return level.reservedAISquadSlots[ squadName ].count

	return 0
}

function GetReservedAISquadSlotsOfClassForTeam( npcClass, team )
{
	local count = 0
	foreach ( table in level.reservedAISquadSlots )
	{
		if ( table.team != team )
			continue

		if ( table.npcClass == npcClass )
			count += table.count
	}

	return count
}
Globalize( GetReservedAISquadSlotsOfClassForTeam )

function IsClassInReservedAISquadSlots_ForSquadName( squadName, npcClass )
{
	if ( squadName in level.reservedAISquadSlots )
	{
		if ( level.reservedAISquadSlots[ squadName ].npcClass == npcClass )
			return true
	}

	return false
}

function SpawnPilotAI( team, squadName, origin, angles, alert = true )
{
    local pilotmodels = file.pilotmodels
    if ( team == TEAM_MILITIA )
        pilotmodels = file.militiapilotmodels
    else if ( team == TEAM_IMC )
        pilotmodels = file.imcpilotmodels

    local pilot = CreateEntity( "npc_soldier" )
    DispatchSpawn( pilot )
    pilot.SetOrigin( origin )
    pilot.SetTeam( team )
    pilot.SetModel( Random( pilotmodels ) )
    SetNPCAsPilot( pilot, true )
    GiveMinionWeapon( pilot, "mp_weapon_rspn101" )
    pilot.SetMaxHealth( 200 )
    pilot.SetHealth( 200 )
    if ( squadName != null )
        SetSquad( pilot, squadName )
    return pilot
}
Globalize( SpawnPilotAI )

function Spawn_TrackedSpectre( team, squadName, origin, angles, alert = true, weapon = null, hidden = false )
{
	local spectre = SpawnSpectre( team, squadName, origin, angles, alert, weapon, hidden )

	Assert( IsAlive( spectre ) )

	ReserveAISlots( team )
	FreeAISlotOnDeath( spectre )

	return spectre
}

function Spawn_TrackedGrunt( team, squadName, origin, angles, alert = true )
{
	// Assert( level.freeAISlots[team] > 0 )

	local soldier = SpawnGrunt( team, squadName, origin, angles, alert )

	Assert( IsAlive( soldier ) )

	ReserveAISlots( team )
	FreeAISlotOnDeath( soldier )

	return soldier
}

function Spawn_TrackedDropPodPilotSquad( team, count, spawnPoint, squadName = null )
{
    return Spawn_TrackedDropPodSquad( "npc_soldier", team, count, spawnPoint, squadName, false, SpawnPilotAI )
}
Globalize( Spawn_TrackedDropPodPilotSquad )

function Spawn_TrackedDropPodGruntSquad( team, count, spawnPoint, squadName = null )
{
	local ai_type = "npc_soldier"
	return Spawn_TrackedDropPodSquad( ai_type, team, count, spawnPoint, squadName )
}
Globalize( Spawn_TrackedDropPodGruntSquad )


function Spawn_TrackedDropPodSpectreSquad( team, count, spawnPoint, squadName = null )
{
	local ai_type = "npc_spectre"
	return Spawn_TrackedDropPodSquad( ai_type, team, count, spawnPoint, squadName )
}
Globalize( Spawn_TrackedDropPodSpectreSquad )


function Spawn_ScriptedTrackedDropPodGruntSquad( team, count, origin, angles, squadName = null, spawnfunc = null, onImpactFunc = null )
{
	local ai_type 		= "npc_soldier"
	local forced 		= true
	local spawnPoint 	= __CreateDummySpawnPoint( origin, angles )

	local soldierEntities = Spawn_TrackedDropPodSquad( ai_type, team, count, spawnPoint, squadName, forced, spawnfunc, onImpactFunc )
	spawnPoint.Kill()

	return soldierEntities
}
Globalize( Spawn_ScriptedTrackedDropPodGruntSquad )


function Spawn_ScriptedTrackedDropPodSpectreSquad( team, count, origin, angles, squadName = null, spawnfunc = null, onImpactFunc = null )
{
	local ai_type 		= "npc_spectre"
	local forced 		= true
	local spawnPoint 	= __CreateDummySpawnPoint( origin, angles )

	if ( spawnfunc == null )
		spawnfunc = SpawnSpectre

	local soldierEntities = Spawn_TrackedDropPodSquad( ai_type, team, count, spawnPoint, squadName, forced, spawnfunc, onImpactFunc )
	spawnPoint.Kill()

	return soldierEntities
}
Globalize( Spawn_ScriptedTrackedDropPodSpectreSquad )


function __CreateDummySpawnPoint( origin, angles )
{
	local spawnPoint 	= CreateScriptRef( origin, angles )
	spawnPoint.s.inUse 	<- false
	return spawnPoint
}


function Spawn_TrackedDropPodSquad( ai_type, team, count, spawnPoint, squadName = null, force = false, spawnfunc = null, onImpactFunc = null )
{
	if ( !IsNPCSpawningEnabled( team ) && !force )
		return []

	if ( !force )
		Assert( count <= GetFreeAISlots(team), "wanted to spawn: " + count + " AI but only " + GetFreeAISlots( team ) + " slots where free" )

	if(!spawnPoint)		// 데이터가 없을 경우에는 리턴
		return

	CommonTrackingInit( ai_type, team, count, squadName )
	spawnPoint.s.inUse = true

	local dropPod = CreatePropDynamic( DROPPOD_MODEL ) // model is set in InitFireteamDropPod()
	InitFireteamDropPod( dropPod )

	local options = {}
	if ( onImpactFunc )
		options.onImpactFunc <- onImpactFunc

	waitthread LaunchAnimDropPod( dropPod, "pod_testpath", spawnPoint.GetOrigin(), spawnPoint.GetAngles(), options )
	if ( force )
		PlayFX( "droppod_impact", spawnPoint.GetOrigin(), spawnPoint.GetAngles() )

	if ( spawnfunc == null )
	{
		if ( ai_type == "npc_spectre" )
			spawnfunc = SpawnSpectre
		else
			spawnfunc = SpawnGrunt
	}

	local soldierEntities = CreateNPCSForDroppod( team, count, spawnPoint.GetOrigin(), spawnPoint.GetAngles(), squadName, force, spawnfunc )
	ActivateFireteamDropPod( dropPod, null, soldierEntities )

	CommonTrackingCleanup( soldierEntities, ai_type, team, count, squadName )
	spawnPoint.s.inUse = false

	return soldierEntities
}
Globalize( Spawn_TrackedDropPodSquad )

function Spawn_TrackedPilotWithTitan( team, spawnPoint )
{
	if ( !IsNPCSpawningEnabled( team ) )
		return []

	if ( !spawnPoint )
		return
	if ( "inUse" in spawnPoint.s )
    spawnPoint.s.inUse <- true
	CreateTitanForTeam( team, spawnPoint, spawnPoint.GetOrigin(), spawnPoint.GetAngles() )
	if ( "inUse" in spawnPoint.s )
	spawnPoint.s.inUse <- false
}

function CreateTitanForTeam( team, spawnPoint, spawnOrigin, spawnAngles )
{
	local titanDataTable = GetRandomTitanLoadout()
	local titans = Random([ "titan_stryder", "titan_atlas", "titan_ogre" ])
	titanDataTable.setFile = titans
	local settings = titanDataTable.setFile
	titanDataTable.primary = Random([
		"mp_titanweapon_arc_cannon",
		"mp_titanweapon_rocket_launcher",
		"mp_titanweapon_40mm",
		"mp_titanweapon_sniper",
		"mp_titanweapon_triple_threat",
		"mp_titanweapon_xo16",
		"mp_titanweapon_shotgun",
		// "mp_weapon_mega3",
	])

	local pilotmodels = file.pilotmodels
	if ( team == TEAM_MILITIA )
	    pilotmodels = file.militiapilotmodels
	else if ( team == TEAM_IMC )
	    pilotmodels = file.imcpilotmodels

	local pilot = CreateEntity( "npc_soldier" )
	DispatchSpawn( pilot )
	pilot.SetOrigin( spawnOrigin )
	pilot.SetTeam( team )
	pilot.SetModel( Random( pilotmodels ) )
	SetNPCAsPilot( pilot, true )
	GiveMinionWeapon( pilot, "mp_weapon_rspn101" )
	pilot.SetMaxHealth( 200 )
	pilot.SetHealth( 200 )

	local title = ""
    
    // Custom logic for varied Pilot names based on Team
    if ( team == TEAM_IMC )
    {
        local imcCodeNames = [
            "Alpha", "Bravo", "Charlie", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet", "Kilo",
            "Lima", "Mike", "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform",
            "Victor", "Whiskey", "Xray", "Yankee", "Zulu", "Steel", "Raven", "Falcon", "Silver", "Roach",
			"Io", "Ganymede", "Callisto", "Europa",
        ]
        title = "Pilot " + Random( imcCodeNames )
    }
    else if ( team == TEAM_MILITIA )
    {
        local militiaNames = [
            "Jackson", "Rodriguez", "Williams", "Wilson", "Moore", "Anderson", "White", "Lewis", "Clark", "Walker",
            "Baker", "Young", "Turner", "Carter", "Evans", "Hill", "Hawkins", "Campbell", "Hanes", "Stokes",
            "Bohr", "Allen", "Turing", "Phillips", "Feynman", "Frey", "Wilkes", "Shaver", "Freeborn", "Gundyr",
			"Barnes", "Hernandez", "Greene",
        ]
        title = "Pilot " + Random( militiaNames )
    }

    // This title is then passed to the spawn function
    thread Spawn_PilotInDroppod( pilot, title, team, spawnPoint )

	wait 2.5
	local titan = CreateNPCTitanFromSettings( settings, team, spawnOrigin, spawnAngles )
	
	if ( !("nukeTitanDamagesOtherTitans" in titan.s) )
		titan.s.nukeTitanDamagesOtherTitans <- true

	// 10% chance to become a Nuke Titan
	if ( RandomFloat( 0.0, 1.0 ) <= 0.1 )
	{
		NPC_SetNuclearPayload( titan, true )
		titan.SetSubclass( eSubClass.nukeTitan )
	}

	if ( titans == "titan_stryder" )
	titan.SetTitle( "#CHASSIS_STRYDER_NAME" )
	else if ( titans == "titan_atlas" )
	titan.SetTitle( "#CHASSIS_ATLAS_NAME" )
	else if ( titans == "titan_ogre" )
	titan.SetTitle( "#CHASSIS_OGRE_NAME" )
	
	local weaponMods = []
	local weaponModPools = {
		mp_titanweapon_40mm            = [ "burst", "extended_ammo", ],                 // "burn_mod_titan_40mm"
		mp_titanweapon_xo16            = [ "extended_ammo", "burst", "accelerator", ],  // "burn_mod_titan_xo16"
		mp_titanweapon_sniper          = [ "extended_ammo", ],
		mp_titanweapon_arc_cannon      = [ null, "capacitor", "burn_mod_titan_arc_cannon", ],  
		mp_titanweapon_rocket_launcher = [ "rapid_fire_missiles", "extended_ammo", ],   // "burn_mod_titan_rocket_launcher"
		mp_titanweapon_triple_threat   = [ "mine_field", "extended_ammo", ],            // "burn_mod_titan_triple_threat"
		mp_titanweapon_shotgun         = [ "extended_ammo", "semi_converter", ],
	}

	local primaryWeapon = titanDataTable.primary
	if ( primaryWeapon in weaponModPools )
	{
		local availableMods = weaponModPools[primaryWeapon]
		local roll = RandomInt( 0, availableMods.len() - 1 )
		local selectedMod = availableMods[roll]

		if ( selectedMod != null )
		{
			weaponMods.append( selectedMod )
		}
	}

	titan.GiveWeapon( titanDataTable.primary, weaponMods )
    titan.TakeOffhandWeapon( 0 )
    titan.TakeOffhandWeapon( 1 )
	titan.SetLookDist( 120000 )
	titan.kv.faceEnemyWhileMovingDistSq = 1024 * 1024
	
	AttritionGiveTitanRandomTacticalAbility( titan )
	GiveTitanRandomShoulderWeapon( titan )
	AllowTeamRodeo( titan, true )
	thread TrackTitan( titan )
	waitthread SuperHotDropGenericTitan_DropIn( titan, spawnOrigin, spawnAngles )
	thread PlayAnim( titan, "at_MP_embark_idle_blended" )
	if ( IsValid( pilot ) && IsValid( titan ) && IsAlive( pilot ) && IsAlive( titan ) )
	{
		pilot.SetOrigin( titan.GetOrigin() )
		pilot.InitFollowBehavior( titan, AIF_FIRETEAM )
	    pilot.EnableBehavior( "Follow" )
		pilot.DisableBehavior( "Assault" )
	    thread NPCPilotEmbarkTitan( pilot, title, titan )
		thread TitanStandUpHandle( pilot, titan )
		return
	}
	else if ( IsValid( titan ) && IsAlive( titan ) )
	    thread PlayAnimGravity( titan, "at_hotdrop_quickstand" )

	return

	thread TitanBrawlAuto_HuntThink( titan, entry )
	thread TitanBrawlAuto_SpottingThink( titan, entry )
}

function TitanStandUpHandle( pilot, titan )
{
	pilot.EndSignal( "OnDestroy" )
	pilot.EndSignal( "OnDeath" )
	titan.EndSignal( "OnDestroy" )
	titan.EndSignal( "OnDeath" )
	OnThreadEnd(
		function() : ( titan )
		{
			if ( IsValid( titan ) && IsAlive( titan ) && !TitanHasPilotInTitan( titan ) )
			thread PlayAnimGravity( titan, "at_hotdrop_quickstand" )
		}
	)
	WaitForever()
}

function AttritionGiveTitanRandomTacticalAbility( titan )
{
	AttritionGiveTitanTacticalAbility( titan, RandomInt( 1, 4 ) )
}

function AttritionGiveTitanTacticalAbility( titan, tacAbility )
{
	local tac = titan.GetOffhandWeapon( tacAbility )
	switch ( tacAbility )
	{
		case 1:
			if ( !IsValid( tac ) )
				titan.GiveOffhandWeapon( "mp_titanability_bubble_shield", 2 )
			titan.SetTacticalAbility( titan.GetOffhandWeapon( 2 ), TTA_WALL )
			break

		case 2:
			if ( !IsValid( tac ) )
				titan.GiveOffhandWeapon( "mp_titanability_smoke", 3 )
			titan.SetTacticalAbility( titan.GetOffhandWeapon( 3 ), TTA_SMOKE )
			break

		default:
			if ( !IsValid( tac ) )
				titan.GiveOffhandWeapon( "mp_titanweapon_vortex_shield", 1 )
			titan.SetTacticalAbility( titan.GetOffhandWeapon( 1 ), TTA_VORTEX )
			break
	}
}

function GiveTitanRandomShoulderWeapon( titan )
{
	local weapons = [
		"mp_titanweapon_salvo_rockets",
		"mp_titanweapon_dumbfire_rockets",
		"mp_titanweapon_shoulder_rockets",
		"mp_titanweapon_homing_rockets",
		]

	GiveTitanShoulderWeapon( titan, Random( weapons ) )
}

//////////////////////////////

function GiveTitanRandomShoulderWeapon( titan )
{
	local weapons = [
		"mp_titanweapon_salvo_rockets",
		"mp_titanweapon_dumbfire_rockets",
		"mp_titanweapon_shoulder_rockets",
		"mp_titanweapon_homing_rockets",
		]

	GiveTitanShoulderWeapon( titan, Random( weapons ) )
}

function GiveTitanShoulderWeapon( titan, shoulderWeapon )
{
	titan.GiveOffhandWeapon( shoulderWeapon, 0 )
	thread CreateTitanRocketPods( titan.GetTitanSoul(), titan )
	thread TitanShoulderWeaponThink( titan )
}

function TitanDisableRocketPods( titan )
{
	if ( "lockedRocketPods" in titan.s && titan.s.lockedRocketPods )
		return

	titan.Signal( "DisableRocketPods" )
}
Globalize( TitanDisableRocketPods )


function TitanHasRocketPods( titan )
{
	return IsValid( titan.GetOffhandWeapon( 0 ) )
}
Globalize( TitanHasRocketPods )


function TitanEnableRocketPods( titan )
{
	if ( "lockedRocketPods" in titan.s && titan.s.lockedRocketPods )
		return

	Assert( IsValid( titan.GetOffhandWeapon( 0 ) ) )
	thread TitanShoulderWeaponThink( titan )
}
Globalize( TitanEnableRocketPods )

function TitanLockRocketPods( titan )
{
	if ( !( "lockedRocketPods" in titan.s ) )
		titan.s.lockedRocketPods <- false

	titan.s.lockedRocketPods = true
}
Globalize( TitanLockRocketPods )

function TitanUnlockRocketPods( titan )
{
	if ( !( "lockedRocketPods" in titan.s ) )
		titan.s.lockedRocketPods <- false

	titan.s.lockedRocketPods = false
}
Globalize( TitanUnlockRocketPods )

function TitanShoulderWeaponThink( titan )
{
	local weapon = titan.GetOffhandWeapon( 0 )

	titan.EndSignal( "OnDeath" )
	titan.EndSignal( "OnDestroy" )
	titan.EndSignal( "Doomed" )
	titan.EndSignal( "DisableRocketPods" )
	weapon.EndSignal( "OnDestroy" )

	local fireFunc

	switch ( weapon.GetClassname() )
	{
		case "mp_titanweapon_salvo_rockets":
			fireFunc = RocketPodsFire_SalvoRockets
			break

		case "mp_titanweapon_dumbfire_rockets":
			fireFunc = RocketPodsFire_DumbfireRockets
			break

		case "mp_titanweapon_shoulder_rockets":
			fireFunc = RocketPodsFire_ShoulderRockets
			break

		case "mp_titanweapon_homing_rockets":
			fireFunc = RocketPodsFire_HomingRockets
			break

		default:
			Assert( 0 , "shoulder weapon " + shoulderWeapon + " not setup for NPC titan use.")
			break
	}

	local max_range 			= weapon.GetWeaponInfoFileKeyField( "npc_max_range" )
	local max_range_sqr 		= pow( max_range, 2 )

	while( 1 )
	{
		wait 0.5

		if ( !titan.GetEnemy() )
			titan.WaitSignal( "OnFoundEnemy" )

		local enemy = titan.GetEnemy()

		if ( !IsValid( enemy ) || !enemy.IsTitan() )
			continue

		if ( DistanceSqr( enemy.GetOrigin(), titan.GetOrigin() ) > max_range_sqr )
			continue

		if ( !titan.CanSee( enemy ) )
			continue

		if ( !IsFacingEnemy( titan, enemy ) )
			continue

		local results = {}
		results.numRocketsFired <- 0
		results.maxRockets 		<- 12
		results.targetLockon 	<- false
		results.cooldown 		<- 0

		local soul = enemy.GetTitanSoul()
		Assert( soul != null )

		waitthread fireFunc( titan, weapon, soul, results )

		if ( !results.numRocketsFired )
			continue

		wait results.cooldown
	}
}


/**************************************************************************\
	salvo rockets
\**************************************************************************/
function RocketPodsFire_SalvoRockets( titan, weapon, soul, results )
{
	titan.EndSignal( "OnDeath" )
	titan.EndSignal( "OnDestroy" )
	titan.EndSignal( "Doomed" )
	titan.EndSignal( "DisableRocketPods" )
	titan.EndSignal( "OnLostEnemy" )
	soul.EndSignal( "OnTitanDeath" )
  	soul.EndSignal( "OnDestroy" )

	local numRockets 			= weapon.GetWeaponModSetting( "burst_fire_count" )
	local fireRate 				= 0//weapon.GetWeaponModSetting( "fire_rate" ) * 0.01

	results.maxRockets 		= numRockets
	results.cooldown 		= weapon.GetWeaponModSetting( "burst_fire_delay" )
	results.numRocketsFired = numRockets

	local attackParams = GetFakedAttackParams( weapon, soul )

	for ( local i = 0; i < numRockets; i++ )
	{
		attackParams.burstIndex = i
		weapon.SetWeaponBurstFireCount( numRockets )
		weapon.GetScriptScope().OnWeaponPrimaryAttack( attackParams )
		wait fireRate
	}
}

/**************************************************************************\
	dumb fire rockets
\**************************************************************************/
function RocketPodsFire_DumbfireRockets( titan, weapon, soul, results )
{
	titan.EndSignal( "OnDeath" )
	titan.EndSignal( "OnDestroy" )
	titan.EndSignal( "Doomed" )
	titan.EndSignal( "DisableRocketPods" )
	titan.EndSignal( "OnLostEnemy" )
	soul.EndSignal( "OnTitanDeath" )
  	soul.EndSignal( "OnDestroy" )

	results.maxRockets 		= 1
	results.cooldown 		= 1.0 / weapon.GetWeaponModSetting( "fire_rate" )
	results.numRocketsFired = 1

	local attackParams = GetFakedAttackParams( weapon, soul )

	weapon.GetScriptScope().OnWeaponPrimaryAttack( attackParams )
}

/**************************************************************************\
	shoulder rockets -> multi target ( 12x misslies )
\**************************************************************************/
function RocketPodsFire_ShoulderRockets( titan, weapon, soul, results )
{
	titan.EndSignal( "OnDeath" )
	titan.EndSignal( "OnDestroy" )
	titan.EndSignal( "Doomed" )
	titan.EndSignal( "DisableRocketPods" )
	titan.EndSignal( "OnLostEnemy" )
	soul.EndSignal( "OnTitanDeath" )
  	soul.EndSignal( "OnDestroy" )

	local maxRockets 			= weapon.GetWeaponModSetting( "smart_ammo_target_max_locks_titan" )
	local minRockets 			= ( maxRockets / 3 ).tointeger()
	local numRockets 			= RandomInt( minRockets, maxRockets + 1 )
	local targeting_time_max 	= weapon.GetWeaponModSetting( "smart_ammo_targeting_time_max" )
	local targetTime 			= numRockets * targeting_time_max

	results.maxRockets 	= maxRockets

	waitthread LockOntoEnemy( titan, weapon, soul, targetTime, results )
	if ( !results.targetLockon )
		return

	local attackParams = GetFakedAttackParams( weapon, soul )

	weapon.SmartAmmo_Enable()
	weapon.SetWeaponBurstFireCount( numRockets )
	weapon.SmartAmmo_SetTarget( soul, numRockets )  // hack: fraction is the number of rockets; same as player weapon

	for ( local i = 0; i < numRockets; i++ )
	{
		attackParams.burstIndex = i
		weapon.GetScriptScope().OnWeaponPrimaryAttack( attackParams )
	}

	local cooldown_time 	= weapon.GetWeaponModSetting( "charge_cooldown_time" )
	local cooldown_delay 	= weapon.GetWeaponModSetting( "charge_cooldown_delay" )
	local rocketFrac 		= numRockets / maxRockets
	cooldown_time *= rocketFrac

	results.cooldown 		= cooldown_time
	results.numRocketsFired = numRockets

	weapon.SmartAmmo_Clear( true )
	if ( IsValid( soul.GetBossPlayer() ) )
		SmartAmmo_ClearCustomFractionSource( weapon, soul.GetBossPlayer() )
}

/**************************************************************************\
	homing rockets -> slaved warheads ( 4x 3-missiles )
\**************************************************************************/
function RocketPodsFire_HomingRockets( titan, weapon, soul, results )
{
	titan.EndSignal( "OnDeath" )
	titan.EndSignal( "OnDestroy" )
	titan.EndSignal( "Doomed" )
	titan.EndSignal( "DisableRocketPods" )
	titan.EndSignal( "OnLostEnemy" )
	soul.EndSignal( "OnTitanDeath" )
  	soul.EndSignal( "OnDestroy" )

	local fireRate 				= 1.0 / weapon.GetWeaponModSetting( "fire_rate" )
	local numRockets 			= 12
	local numBursts 			= weapon.GetWeaponModSetting( "smart_ammo_max_targeted_burst" )
	local rocketsPerBurst 		= ( numRockets / numBursts ).tointeger()
	local targetTime 			= weapon.GetWeaponModSetting( "smart_ammo_targeting_time_max" )

	results.maxRockets 	= numRockets
	results.cooldown 	= weapon.GetWeaponModSetting( "burst_fire_delay" )

	waitthread LockOntoEnemy( titan, weapon, soul, targetTime, results )
	if ( !results.targetLockon )
		return

	weapon.SmartAmmo_SetTarget( soul, rocketsPerBurst )
	results.numRocketsFired = numRockets

	for ( local i = 0; i < numBursts; i++ )
	{
		local attackParams = GetFakedAttackParams( weapon, soul )

		attackParams.burstIndex = i
		weapon.SmartAmmo_Enable()
		weapon.SetWeaponBurstFireCount( rocketsPerBurst )
		weapon.GetScriptScope().OnWeaponPrimaryAttack( attackParams )

		wait fireRate

		if ( !( soul.GetTitan().IsPlayer() ) && IsValid( soul.GetBossPlayer() ) )
			SmartAmmo_ClearCustomFractionSource( weapon, soul.GetBossPlayer() )
	}

	weapon.SmartAmmo_Clear( true )
	if ( IsValid( soul.GetBossPlayer() ) )
		SmartAmmo_ClearCustomFractionSource( weapon, soul.GetBossPlayer() )
}

/**************************************************************************\
	HACKED LOCK ON FOR NPCS
\**************************************************************************/
function LockOntoEnemy( titan, weapon, soul, targetTime, results )
{
	titan.EndSignal( "OnDeath" )
	titan.EndSignal( "OnDestroy" )
	titan.EndSignal( "Doomed" )
	titan.EndSignal( "DisableRocketPods" )
	titan.EndSignal( "OnLostEnemy" )
	soul.EndSignal( "OnTitanDeath" )
  	soul.EndSignal( "OnDestroy" )
	titan.EndSignal( "OnLostTarget" )

	local currTargetTime 	= 0.0
	local humanFakedDelay 	= 1.5
	local giveUpTime 		= 4.0
	local giveUpTargetTime 	= Time() + targetTime + giveUpTime + humanFakedDelay

	thread SetSignalDelayed( titan, "OnLostTarget", giveUpTargetTime )

	local customFractionSource = []
	OnThreadEnd(
		function() : ( titan, weapon, soul, giveUpTargetTime, customFractionSource )
		{
			if ( !IsValid( weapon ) )
				return

			if ( !customFractionSource.len() )
				return

			Assert( customFractionSource.len() == 1 )

			if ( !IsValid( customFractionSource[ 0 ] ) )
				return

			SmartAmmo_ClearCustomFractionSource( weapon, customFractionSource[ 0 ] )
		}
	)

	local interval 			= 0.2
	while( 1 )
	{
		local newLock = true
		local lockWasPlayer = false
		local lockIsPlayer = false

		while( titan.CanSee( soul.GetTitan() ) && IsFacingEnemy( titan, soul.GetTitan() ) )
		{
			if ( soul.GetTitan().IsPlayer() )
				lockIsPlayer = true

			if ( lockWasPlayer != lockIsPlayer )
				newLock = true

			if ( newLock )
			{
				if ( soul.GetTitan().IsPlayer() )
				{
					customFractionSource.append( soul.GetBossPlayer() )
					SmartAmmo_SetCustomFractionSource( weapon, customFractionSource[ 0 ], targetTime )
				}
				else if ( customFractionSource.len() )
				{
					SmartAmmo_ClearCustomFractionSource( weapon, customFractionSource[ 0 ] )
					Assert( customFractionSource.len() == 1 )
					customFractionSource.remove( 0 )
				}

				lockWasPlayer = true
				lockIsPlayer = true
				newLock = false
			}

			if ( currTargetTime >= targetTime + humanFakedDelay )
			{
				results.targetLockon = true
				return
			}

			wait interval
			currTargetTime += interval
		}

		while( !titan.CanSee( soul.GetTitan() ) || !IsFacingEnemy( titan, soul.GetTitan() ) )
		{
			if ( customFractionSource.len() )
			{
				SmartAmmo_ClearCustomFractionSource( weapon, customFractionSource[ 0 ] )
				Assert( customFractionSource.len() == 1 )
				customFractionSource.remove( 0 )
			}

			wait interval
			currTargetTime -= interval * 1.5
			if ( currTargetTime < 0 )
				currTargetTime = 0.0
		}
	}
}

function GetFakedAttackParams( weapon, enemySoul )
{
	local titan 	= weapon.GetWeaponOwner()
	local soul = titan.GetTitanSoul()
	Assert( IsValid( soul ) && IsValid( soul.rocketPod ) )

	local model		= soul.rocketPod.model
	local attachID 	= model.LookupAttachment( "muzzle_flash" )
	local origin 	= model.GetAttachmentOrigin( attachID )
	local vec 		= null

	local enemy 	= enemySoul.GetTitan()

	if ( enemy )
	{
		vec = enemy.EyePosition() - titan.EyePosition()
		vec.Normalize()
	}
	else
	{
		vec = titan.GetViewVector()
	}

	local attackParams = {}
	attackParams.burstIndex <- 0
	attackParams.pos <- origin
	attackParams.dir <- vec

	return attackParams
}

//////////////////////////////

function SuperHotDropGenericTitan_DropIn( titan, origin, angles )
{
	titan.EndSignal( "OnDeath" )

//	printt( "TitanHotDrop" )
//origin = Vector(-2257.346924, -2599.757080, -275.556885)
//angles = Vector(0.000000, -177.883041, 0.000000)

//	printt( "origin: " + origin )
//	printt( "angles: " + angles )
	titan.s.disableAutoTitanConversation <- true

	OnThreadEnd(
		function() : ( titan )
		{
			if ( !IsValid( titan ) )
				return

			//delete titan.s.disableAutoTitanConversation //Don't delete here, otherwise Auto Titan will start talking about engaging enemy soldiers while kneeling down.
			titan.DisableRenderAlways()

			DeleteAnimEvent( titan, "titan_impact", OnReplacementTitanImpact )
			DeleteAnimEvent( titan, "second_stage", OnReplacementTitanSecondStage )
		}
	)

	HideName( titan )
	titan.UnsetUsable() //Stop titan embark before it lands
	AddAnimEvent( titan, "titan_impact", OnReplacementTitanImpact )
	AddAnimEvent( titan, "second_stage", OnReplacementTitanSecondStage, origin )
	HideTitanEyePartial( titan )

	local animation
	local sfxFirstPerson = "titan_hot_drop_turbo_begin"
	local sfxThirdPerson = "titan_hot_drop_turbo_begin_3P"

	animation = "at_hotdrop_drop_2knee_turbo"

	local impactTime = GetHotDropImpactTime( titan, animation )
	local result = titan.Anim_GetAttachmentAtTime( animation, "OFFSET", impactTime )
	local maxs = titan.GetBoundingMaxs()
	local mins = titan.GetBoundingMins()
	local mask = titan.GetPhysicsSolidMask()
	ModifyOriginForDrop( origin, mins, maxs, result.position, mask )


	titan.SetInvulnerable() // Make Titan invulnerable until bubble shield is up

	//DrawArrow( origin, angles, 10, 150 )
	titan.EnableRenderAlways()

	EmitSoundAtPosition( origin, sfxThirdPerson )

	SetStanceKneel( titan.GetTitanSoul() )

	waitthread PlayAnimTeleport( titan, animation, origin, angles )

	titan.ClearInvulnerable() //Make Titan vulnerable again once he's landed

}

function OnReplacementTitanSecondStage( titan, origin )
{
	local sfxFirstPerson = "titan_drop_pod_turbo_landing"
	local sfxThirdPerson = "titan_drop_pod_turbo_landing_3P"
	local player = titan.GetBossPlayer()
	EmitDifferentSoundsAtPositionForPlayerAndWorld( sfxFirstPerson, sfxThirdPerson, origin, player )
}

function OnReplacementTitanImpact( titan )
{
	ShowName( titan )
	thread CreateGenericBubbleShield( titan, titan.GetOrigin(), titan.GetAngles() )
	OnHotdropImpact( titan )
}

function CommonTrackingInit( ai_type, team, count, squadName )
{
	Assert( ai_type != null )
	ReserveAISlots( team, count )
	ReserveSquadSlots( squadName, count, ai_type, team )
}
Globalize( CommonTrackingInit )


function CommonTrackingCleanup( guys, ai_type, team, count, squadName )
{
	Assert( ai_type != null )
	if ( count != guys.len() )
		ReleaseAISlots( team, count - guys.len() )
	ReleaseSquadSlots( squadName, count, ai_type )

	foreach ( npc in guys )
		FreeAISlotOnDeath( npc )
}
Globalize( CommonTrackingCleanup )


function Spawn_TrackedZipLineGruntSquad( team, count, spawnPoint, squadName = null )
{
	local ai_type = "npc_soldier"
	local dropTable = CreateZipLineSquadDropTable( team, count, spawnPoint, squadName )
	return Spawn_TrackedZipLineSquad( ai_type, spawnPoint, dropTable )
}
Globalize( Spawn_TrackedZipLineGruntSquad )


function Spawn_TrackedZipLineSpectreSquad( team, count, spawnPoint, squadName = null )
{
	local ai_type = "npc_spectre"
	local dropTable = CreateZipLineSquadDropTable( team, count, spawnPoint, squadName )
	return Spawn_TrackedZipLineSquad( ai_type, spawnPoint, dropTable )
}
Globalize( Spawn_TrackedZipLineSpectreSquad )


function Spawn_ScriptedTrackedZipLineGruntSquad( team, count, origin, angles, squadName = null, spawnfunc = null )
{
	local ai_type 		= "npc_soldier"
	local forced 		= true
	local spawnPoint 	= __CreateDummySpawnPoint( origin, angles )
	local dropTable 	= CreateZipLineSquadDropTable( team, count, spawnPoint, squadName, forced, spawnfunc )

	local soldierEntities = Spawn_TrackedZipLineSquad( ai_type, spawnPoint, dropTable, forced )
	spawnPoint.Kill()

	return soldierEntities
}
Globalize( Spawn_ScriptedTrackedZipLineGruntSquad )


function Spawn_ScriptedTrackedZipLineSpectreSquad( team, count, origin, angles, squadName = null, spawnfunc = null )
{
	local ai_type 		= "npc_spectre"
	local forced 		= true
	local spawnPoint 	= __CreateDummySpawnPoint( origin, angles )
	local dropTable 	= CreateZipLineSquadDropTable( team, count, spawnPoint, squadName, forced, spawnfunc )

	local soldierEntities = Spawn_TrackedZipLineSquad( ai_type, spawnPoint, dropTable, forced )
	spawnPoint.Kill()

	return soldierEntities
}
Globalize( Spawn_ScriptedTrackedZipLineSpectreSquad )


function CreateZipLineSquadDropTable( team, count, spawnPoint, squadName, force = null, spawnfunc = null )
{
	if ( spawnfunc == null )
		spawnfunc = SpawnGrunt

	if(!spawnPoint)		// 스폰포인트가 없으면 스킵
		return

	local drop			= CreateDropshipDropoff()
	drop.origin 		= spawnPoint.GetOrigin()
	drop.yaw 			= spawnPoint.GetAngles().y
	drop.dist 			= 768
	drop.count 			= count
	drop.team 			= team
	drop.squadname 		= squadName
	drop.npcSpawnFunc 	= spawnfunc
	drop.style 			= eDropStyle.ZIPLINE_NPC
	drop.assaultEntity 	<- spawnPoint

	if ( force )
		drop.style			= eDropStyle.FORCED

	return drop
}
Globalize( CreateZipLineSquadDropTable )


function Spawn_TrackedZipLineSquad( ai_type, spawnPoint, dropTable, force = false )
{
	if(!spawnPoint)
		return

	local team 		= dropTable.team
	local count 	= dropTable.count
	local squadname = dropTable.squadname
	Assert( team != null )
	Assert( squadname != null )

	if ( !IsNPCSpawningEnabled( team ) && !force )
		return []

	if ( !force )
		Assert( count <= GetFreeAISlots(team), "wanted to spawn: " + count + " AI but only " + GetFreeAISlots( team ) + " slots where free" )

	CommonTrackingInit( ai_type, team, count, squadname )
	spawnPoint.s.inUse = true

	thread RunDropshipDropoff( dropTable )

	local soldierEntities = []
	if ( dropTable.success )
	{
		// get the guys that spawned
		local results = WaitSignal( dropTable, "OnDropoff" )
		Assert( "guys" in results )

		if ( results.guys )
			soldierEntities = results.guys
	}

	CommonTrackingCleanup( soldierEntities, ai_type, team, count, squadname )
	spawnPoint.s.inUse = false

	return soldierEntities
}
Globalize( Spawn_TrackedZipLineSquad )


function FreeAISlotOnDeath( soldier )
{
	Assert( IsAlive( soldier ), soldier + " is not alive!" )
	thread FreeAISlotOnDeathThread( soldier )
}

function FreeAISlotOnDeathThread( soldier )
{
	soldier.EndSignal( "OnDestroy" )

	local team = soldier.GetTeam()	//wouldn't leeched spectres break team AI slot counts?
	OnThreadEnd( function() : (team) { ReleaseAISlots( team ) } )

	soldier.WaitSignal( "OnDeath" )
}



//////////////////////////////////////////////////////////
function SetupTeamDeathmatchNPCs()
{
	FlagWait( "ReadyToStartMatch" )

	if ( InitFrontLine() )
	{
		FlagSet( "FrontlineInitiated" )

		local waitTime = GameTime.TimeLeftSeconds() - GetDropPodAnimDuration() + 3
		if ( GetGameState() <= eGameState.Prematch && waitTime > 0 )
			wait waitTime

		thread TeamDeathmatchSpawnNPCsThink()
    }
}

function TeamDeathmatchSpawnNPCsThink()
{
    while ( GetGameState() < eGameState.Playing )
    {
        wait 1
    }

    // Clear campaign-specific disable flags
    if ( GetCurrentPlaylistName() == "campaign_carousel" )
    {
        if ( Flag( "Disable_IMC" ) ) FlagClear( "Disable_IMC" )
        if ( Flag( "Disable_MILITIA" ) ) FlagClear( "Disable_MILITIA" )
    }

    local teams = [TEAM_IMC, TEAM_MILITIA]
    local mode = GameRules.GetGameMode()
    local extraGrunts = 0
    
    if ( !( "modifyAISlots" in level ) )
        level.modifyAISlots <- { [TEAM_IMC] = 0, [TEAM_MILITIA] = 0 }

	// TITAN SPAWNING
	function IsTitanMode( mode )
	{
		switch( mode )
		{
			case ATTRITION:
			case CAPTURE_POINT:
			case TEAM_DEATHMATCH:
			case TITAN_BRAWL:
			case LAST_TITAN_STANDING:
			case CAPTURE_THE_FLAG:
			case COOPERATIVE:
				return true
		}
		return false
	}

	if ( !Flag("Disable_IMC") && IsTitanMode(mode) )
	{
		thread SpawnPilotWithTitans( TEAM_IMC )
	}

	if ( !Flag( "Disable_MILITIA" ) && IsTitanMode(mode) ) 
	{
		thread SpawnPilotWithTitans( TEAM_MILITIA )
	}

	// WAVE SPAWNING (Spectre variants and cloak drones won't spawn in Titan-based modes)
	if ( mode == ATTRITION || mode == CAPTURE_POINT || mode == TEAM_DEATHMATCH || mode == CAPTURE_THE_FLAG )
	{
		if ( !Flag( "Disable_IMC" ) )
		{
			thread SuicideSpectreWaveThink( TEAM_IMC )
			thread CloakDroneWaveThink( TEAM_IMC )
			thread SniperSpectreWaveThink( TEAM_IMC )
		}
		if ( !Flag( "Disable_MILITIA" ) )
		{
			thread SuicideSpectreWaveThink( TEAM_MILITIA )
			thread CloakDroneWaveThink( TEAM_MILITIA )
			thread SniperSpectreWaveThink( TEAM_MILITIA )
		}
	}
    
    while ( IsNPCSpawningEnabled() )
    {
        extraGrunts = GetGruntBonusForTeam( TEAM_IMC )

        level.modifyAISlots[ TEAM_IMC ] = extraGrunts * -1
        level.modifyAISlots[ TEAM_MILITIA ] = extraGrunts

        if ( !Flag( "Disable_IMC" ) )
            thread TeamDeathmatchSpawnNPCs( TEAM_IMC )

        if ( !Flag( "Disable_MILITIA" ) )
            thread TeamDeathmatchSpawnNPCs( TEAM_MILITIA )

        wait level.npcRespawnWait
    }
}

function GetGruntBonusForTeam( team )
{
	local titanCompare = CompareTitanTeamCount( team )

	// must have at least 3 titan difference
	if ( abs( titanCompare ) <= 2 )
		return 0

	if ( titanCompare > 0 )
	{
		titanCompare -= 1
	}
	else
	{
		titanCompare += 1
	}

	// a titan is worth how many grunts?
	return titanCompare * 2
}

function TeamDeathmatchSpawnNPCs( team )
{
	local numFreeSlots = GetFreeAISlots( team )

	while ( numFreeSlots >= GetSpawnSquadSize( team ) )
	{
		// this will do all the heavy lifting of where and how many to spawn and what they should do once they are in the match.
		thread SpawnFrontlineSquad( team, numFreeSlots )

		// add a little wait so that we don't spawn squads at the exact same time.
		wait RandomFloat( 0.8, 2.0 )

		// the function above will have used up some free slots, lets see how many remain
		numFreeSlots = GetFreeAISlots( team )
	}

}

function SpawnFrontlineSquad( team, numFreeSlots )
{
	if ( !IsNPCSpawningEnabled() )
		return

	local shouldSpawnSpectre = ShouldSpawnSpectre( team )

	local squadIndex = TryGetSmallestValidSquad( team, shouldSpawnSpectre )
	if ( squadIndex == null )
		return

	local squadName = MakeSquadName( team, squadIndex )
	local squadSize = min( numFreeSlots, GetSpawnSquadSize( team ) )
	Assert( squadSize <= GetFreeAISlots( team ), "Squadsize " + squadSize + " is greater than remaining ai slots " + GetFreeAISlots( team ) )

	local inGracePeriod = GameTime.PlayingTime() < START_SPAWN_GRACE_PERIOD
	local inGameState = GetGameState() <= eGameState.Prematch || GetGameState() ==  eGameState.SwitchingSides
	local useStartSpawn = inGameState || inGracePeriod
	local spawnPointArray

	if ( useStartSpawn )
	{
		spawnPointArray = SpawnPoints_GetDropPodStart( team )

		if ( !spawnPointArray.len() )
		{
			spawnPointArray = SpawnPoints_GetDropPod()
			useStartSpawn = false
		}
	}
	else
	{
		spawnPointArray = SpawnPoints_GetDropPod()
	}

	//! 스폰포인트가 없으면 스킵
	if(spawnPointArray.len() < 1)
	{
		return
	}
	Assert( spawnPointArray.len() )

	local spawnPoint = GetFrontlineSpawnPoint( spawnPointArray, team, squadIndex, shouldSpawnSpectre, useStartSpawn )
	Assert( spawnPoint )
	++level.aiSpawnCounter[ team ]

	/////////////////////////////
	local npcArray
    local allowSnipers = GameTime.PlayingTime() > 120.0     // 2 min
    local roll = RandomFloat( 0, 1 ) 

    if ( shouldSpawnSpectre )
	{
        npcArray = Spawn_TrackedDropPodSpectreSquad( team, squadSize, spawnPoint, squadName )
    }
	else
	{
		if ( Flag( "DisableDropships" ) || GameRules.GetGameMode() == EXFILTRATION )
		{
			Assert( squadSize <= GetFreeAISlots(team) )
			npcArray = Spawn_TrackedDropPodGruntSquad( team, squadSize, spawnPoint, squadName )
		}
		else
		{
			Assert( squadSize <= GetFreeAISlots(team) )
			if ( level.aiSpawnCounter[ team ] % 3 == 0 ) // 1 in every 3 grunt squad comes in via ship
				npcArray = Spawn_TrackedZipLineGruntSquad( team, squadSize, spawnPoint, squadName )
			else
				npcArray = Spawn_TrackedDropPodGruntSquad( team, squadSize, spawnPoint, squadName )
		}
	}

	// Route the squad based on gamemode. Frontline-based modes use the old path;
	// CTF gets dynamic objective logic via SquadFlagRunThink.
	if ( GameRules.GetGameMode() == CAPTURE_THE_FLAG )
	{
		if ( CTF_DEBUG )
			printt( "[CTF_AI] SpawnFrontlineSquad dispatching squadIndex", squadIndex, "to AssaultCTF for team", team )
		AssaultCTF( npcArray, squadIndex )
	}
	else
	{
		// make the squad assault the correct frontline
		SquadAssaultFrontline( npcArray, squadIndex )
	}
}


function SuicideSpectreWaveThink( team )
{
	// Prevent Spectre variants from spawning in the Campaign
	if ( GetCurrentPlaylistName() == "campaign_carousel" )
		return

    // Wait until the 3.5-minute mark before starting waves, can spawn as soon as 4.5 minutes
    wait 210.0 + RandomFloat( 0.0, 45.0 )

    while ( IsNPCSpawningEnabled() )
    {
        // Wait between 1 to 3.5 min between waves
        wait RandomFloat( 60.0, 210.0 )

        // Find valid spawn points for the wave
        local spawnPoints = SpawnPoints_GetDropPod()
        
        // Define how many pods you want in the wave (e.g., 3 pods of 4 = 12 spectres)
        local podsToSpawn = 3
        local squadSize = 4
        local squadName = MakeSquadName( team, GetIndexSmallestSquad( team ) )

        for ( local i = 0; i < podsToSpawn; i++ )
        {
            if ( spawnPoints.len() > i )
            {
                local sp = spawnPoints[i]
                
                // Spawn the pod using force = true to bypass max AI limits
                Spawn_TrackedDropPodSquad( "npc_spectre", team, squadSize, sp, squadName, true, SpawnSuicideSpectre )
                
                // Add a tiny stagger so the drop pods don't clip into each other
                wait RandomFloat( 0.5, 1.5 ) 
            }
        }
    }
}

function CloakDroneWaveThink( team )
{
	// Prevent Cloak Drones from spawning in the Campaign
	if ( GetCurrentPlaylistName() == "campaign_carousel" )
		return

    // Wait until the 3-minute mark before starting waves, can spawn as soon as 4 minutes
    wait 180.0 + RandomFloat( 0.0, 45.0 )

    while ( IsNPCSpawningEnabled() )
    {
        // Wait between 1 to 2.5 min between drone waves
        wait RandomFloat( 60.0, 150.0 )

        // Find valid spawn points for the wave using existing drop pod points
        local spawnPoints = SpawnPoints_GetDropPodStart( team ) 
		if ( spawnPoints.len() == 0 )
			spawnPoints = SpawnPoints_GetDropPod()
        
        // Define how many drones you want per wave
        local dronesToSpawn = RandomIntRange( 0, 2 )

		for ( local i = 0; i < dronesToSpawn; i++ )
		{
			if ( spawnPoints.len() > 0 )
			{
				// Pick a random spawn point instead of using 'i'
				local sp = spawnPoints[ RandomInt( spawnPoints.len() ) ]
				SpawnCloakDrone( team, sp.GetOrigin(), sp.GetAngles() )
				wait RandomFloat( 0.5, 1.5 ) 
			}
        }
    }
}

function SniperSpectreWaveThink( team )
{
	// Prevent Spectre variants from spawning in the Campaign
	if ( GetCurrentPlaylistName() == "campaign_carousel" )
		return

    // Wait until the 1-minute mark before starting waves, can spawn as soon as 2 minutes
    wait 60.0 + RandomFloat( 0.0, 45.0 )

    while ( IsNPCSpawningEnabled() )
    {
        // Wait a set interval before rolling for the next potential wave
        wait RandomFloat( 60.0, 150.0 )

        // 15% chance to spawn the sniper pods
        if ( RandomFloat( 0.0, 1.0 ) > 0.15 )
            continue

        // Find valid spawn points for the wave
        local spawnPoints = SpawnPoints_GetDropPod()
        
        // Define how many pods you want in the wave
        local podsToSpawn = 2
        local squadSize = 3
      
        local squadName = MakeSquadName( team, GetIndexSmallestSquad( team ) )

        for ( local i = 0; i < podsToSpawn; i++ )
        {
            if ( spawnPoints.len() > i )
            {
                local sp = spawnPoints[i]
                
                // Spawn the pod using force = true to bypass max AI limits
                Spawn_TrackedDropPodSquad( "npc_spectre", team, squadSize, sp, squadName, true, SpawnSniperSpectre )
                
                // Add a tiny stagger so the drop pods don't clip into each other
                wait RandomFloat( 0.5, 1.5 ) 
            }
        }
    }
}


function Spawn_TrackedPilotWithTitan_Delayed( team, spawnPoint )
{
	local mode = GameRules.GetGameMode()
    if ( mode == TITAN_BRAWL || mode == LAST_TITAN_STANDING )
    {
        wait 0.0  // Titans spawn instantly in Titan Brawl and LTS
    }

    else
    {
        wait RandomFloat( 20, 90 )   // Titan spawn delay in seconds 
    } 

    if ( !IsNPCSpawningEnabled( team ) )
        return
    if ( !IsSpawnpointValidDrop( spawnPoint, team ) )
        return
        
    Spawn_TrackedPilotWithTitan( team, spawnPoint )
}


function SpawnPilotWithTitans( team )
{
	local waittime = 10.0
	
	if ( GameRules.GetGameMode() == TITAN_BRAWL || GameRules.GetGameMode() == LAST_TITAN_STANDING )
	{
		waittime = 0.0
	}

	wait waittime
    
	while( true )
	{
		if ( !IsNPCSpawningEnabled() || SpawnPoints_GetTitan().len() <= 0 )
			return

		local shouldSpawnPilotWithTitan = ShouldSpawnPilotWithTitan( team )
        
		if ( shouldSpawnPilotWithTitan )
		{
			local spawnpoints = SpawnPoints_GetTitan()
			local SpawnPoints = []
            
			foreach( spawnpoint in spawnpoints )
			{
				if ( IsValid( spawnpoint ) && IsSpawnpointValidDrop( spawnpoint, team ) )
					SpawnPoints.append( spawnpoint )
			}

			if ( SpawnPoints.len() <= 0 )
			{
				thread SpawnPilotWithTitans( team )
				return
			}
            
			local spawnPoint = Random( SpawnPoints )

			thread Spawn_TrackedPilotWithTitan_Delayed( team, spawnPoint )
            
			if ( team in file.spawnedtitans )
				file.spawnedtitans[team] <- file.spawnedtitans[team] + 1
			else
				file.spawnedtitans[team] <- 1
		}
        
		// Use a near-instant polling rate for Brawl/LTS, and the default wait for everything else
		if ( GameRules.GetGameMode() == TITAN_BRAWL || GameRules.GetGameMode() == LAST_TITAN_STANDING )
		{
			wait 0.5
		}
		else
		{
			wait level.npcRespawnWait
		}
	}
}

function ShouldSpawnPilotWithTitan( team ) // Titan Spawns per Team
{
    if ( !(team in file.spawnedtitans) )

        return true
    local players = GetPlayerArray()
    if ( players.len() == 0 )
        return false // If no player is in yet, don't spawn
    
    local playerTeam = players[0].GetTeam()
    
    // Titan NPC spawn limit
    local limit = 0
	switch ( GameRules.GetGameMode() )
	{
		case TITAN_BRAWL:
		case LAST_TITAN_STANDING:
			limit = ( team == playerTeam ) ? 3 : 6   // 3 for your team, 6 for enemy team
			break

		case COOPERATIVE:
			limit = ( team == playerTeam ) ? 3 : 0   // 3 for your team
			 
		default:
			// Attrition, Hardpoint, Campaign, 
			limit = ( team == playerTeam ) ? 2 : 5   // 2 for your team, 5 for enemy team
			break
	}

	local mapName = GetMapName()
	if ( mapName == "mp_npe" )
	{
		limit = ( team == playerTeam ) ? 1 : 3
	}		

    return file.spawnedtitans[team] < limit
}

function Coop_SpawnTitansAfterDelay()
{
	// Wait 90 in-game seconds
	wait 90.0
	
	// Start spawning Titans for friendly team (TEAM_MILITIA in Coop)
	thread SpawnPilotWithTitans( TEAM_MILITIA )
}


function GetIndexSmallestSquad( team )
{
	local smallestSize = null
	local squadIndex

	for( local index = 0; index < level.aiSquadCount; index++ )
	{
		local squadName = MakeSquadName( team, index )

		local squadSize = GetNPCSquadSize( squadName )
		squadSize += GetReservedAISquadSlots( squadName )	// add on any reserved AI squad slots

		if ( squadSize < smallestSize || smallestSize == null )
		{
			smallestSize = squadSize
			squadIndex = index
		}
	}

	Assert( squadIndex != null )
	return squadIndex
}

// Whichever type of guy we want to spawn, we have to make sure there is a squad for him.
//  - This means, an empty squad, OR a squad with guys of that type already in it.
//  - NOTE returns null if there's no valid squad for the guy
function TryGetSmallestValidSquad( team, wantSpectreSquad )
{
	local classnameToMatch = "npc_soldier"
	if ( wantSpectreSquad )
		classnameToMatch = "npc_spectre"

//	printt( "Trying to spawn in", classnameToMatch )

	local smallestSize = null
	local squadIndex = null

	for ( local index = 0; index < level.aiSquadCount; index++ )
	{
		local squadName = MakeSquadName( team, index )

		// we only want squads containing npcs with the same classname
		if ( !SquadValidForClass( squadName, classnameToMatch ) )
			continue

		local squadSize = GetReservedSquadSize( squadName )

		if ( squadSize < smallestSize || smallestSize == null )
		{
			smallestSize = squadSize
			squadIndex = index
		}
	}

//	printt( "adding", classnameToMatch, "to squad index", squadIndex )
	return squadIndex
}

function GetReservedSquadSize( squadName )
{
	local squadSize = GetNPCSquadSize( squadName )
	squadSize += GetReservedAISquadSlots( squadName )	// add on any reserved AI squad slots
	return squadSize
}

function SquadValidForClass( squadName, classnameToMatch )
{
	if ( GetReservedAISquadSlots( squadName ) )
	{
		// if we have reserved squad slots they must be reserved by the correct class.
		if ( !IsClassInReservedAISquadSlots_ForSquadName( squadName, classnameToMatch ) )
			return false
	}

	local squadSize = GetNPCSquadSize( squadName )

	// empty squads are legit for any class;
	//  also, can't GetNPCArrayBySquad if there are no NPCs with that squad set
	if ( !squadSize )
	{
		//printt( "squad is empty", squadName )
		return true
	}

	local checkSquad = GetNPCArrayBySquad( squadName )

	foreach ( guy in checkSquad )
	{
		if ( IsValid( guy ) && guy.GetClassname() != classnameToMatch )
			return false
	}

	//printt( "all guys are valid in", squadName )
	//Dump( checkSquad )
	return true
}


function GetFrontlineSpawnPoint( spawnPointArray, team, squadIndex, shouldSpawnSpectre, useStartSpawn )
{
	local frontlinePoint = GetFrontlineGoal( squadIndex, team, shouldSpawnSpectre )
	local combatDir = GetTeamCombatDir( file.currentFrontline, team )
	local edgeOrigin = frontlinePoint.GetOrigin() - combatDir * FRONTLINE_NPC_SPAWN_OFFSET

	SpawnPoints_InitRatings( null )

	foreach ( spawnpoint in spawnPointArray )
		RateFrontLineNPCSpawnpoint( spawnpoint, team, edgeOrigin, combatDir )

	if ( useStartSpawn )
	{
		SpawnPoints_SortDropPodStart()
		spawnPointArray = SpawnPoints_GetDropPodStart( team )
	}
	else
	{
		SpawnPoints_SortDropPod()
		spawnPointArray = SpawnPoints_GetDropPod()
	}

	foreach ( spawnpoint in spawnPointArray )
	{
		if ( IsSpawnpointValidDrop( spawnpoint, team ) )
			return spawnpoint
	}

	// 테스트 맵일 경우에는 이상한 정보가 올수 있다.
	//if(level.isTestmap)
	//	return

	// we will always return a spawnpoint even if it's a bad one.
	return spawnPointArray[0]
}


//////////////////////////////////////////////////////////
function InitFrontLine()
{
	file.nextOverrunCheck <- Time()
	file.frontlineGroupTable <- {}
	file.currentFrontline <- null

	file.frontlineTeamSide <-
	{
		[TEAM_IMC] = 0,
		[TEAM_MILITIA] = 1
	}

	file.npcDeathPerTeam <-
	{
		[TEAM_UNASSIGNED] = [],
		[TEAM_IMC] = [],
		[TEAM_MILITIA] = []
	}

	file.playerDeathPerTeam <-
	{
	 	[TEAM_UNASSIGNED] = [],
	 	[TEAM_IMC] = [],
	 	[TEAM_MILITIA] = []
	 }

	InitFrontlineGroups()
	if ( !file.frontlineGroupTable.len() )
		return false

	AddDeathCallback( "npc_soldier", FrontlineDeathNPC )
	AddDeathCallback( "npc_spectre", FrontlineDeathNPC )
	AddDeathCallback( "player", FrontlineDeath )
	AddDeathCallback( "npc_titan", FrontlineDeath )

	// select current frontline group
	// this will most likely be the one closest to the center of the map
	local spawnpoints = SpawnPoints_GetDropPodStart( TEAM_ANY )
	local mapCenter = GetMapCenter( spawnpoints )

	// get center most frontline to start with
	local oldDist = 100000 * 100000
	foreach( group, groupTable in file.frontlineGroupTable )
	{
		local dist = Distance2DSqr( mapCenter, groupTable.frontlineCenter )
		if ( dist > oldDist )
			continue

		oldDist = dist
		file.currentFrontline = groupTable	// set to closest group
	}

	SetFrontlineSides( file.currentFrontline, TEAM_MILITIA )

	DebugSendClientFrontlineAllPlayers()

	return true
}



//////////////////////////////////////////////////////////
function GameModeRemoveFrontline( entArray )
{
	// remove frontlines not for the current gamemode
	local keepUndefined = false
	local gameMode = GameRules.GetGameMode()
	switch ( gameMode )
	{
		case CAPTURE_THE_FLAG:
		case LAST_TITAN_STANDING:
		case WINGMAN_LAST_TITAN_STANDING:
			break
		default:
			keepUndefined = true
			gameMode = TEAM_DEATHMATCH
			break
	}

	local gamemodeKey = "gamemode_" + gameMode
	for ( local index = 0; index < entArray.len(); index++ )
	{
		local ent = entArray[ index ]

		if ( ent.HasKey( gamemodeKey ) && ent.kv[gamemodeKey] == "1" )
			continue	// if the key exist and it's true then keep the frontline
		else if ( !ent.HasKey( gamemodeKey ) && keepUndefined )
			continue	// if the key doesn't exist but keepUndefined is true keep the frontline

		// delete and remove it from the array
		ent.Destroy()
		entArray.remove( index )
		index--	// decrement to counteract the regular increment in the for loop
	}
}

//////////////////////////////////////////////////////////
function InitFrontlineGroups()
{
	// find all info_frontline ents
	local entArray = GetEntArrayByClass_Expensive( "info_frontline" )
	GameModeRemoveFrontline( entArray )

	if ( entArray.len() == 0 )
		entArray = CreateTempFrontline()

	local spectreNodeArray = []

	foreach ( info_frontline in entArray )
	{
		if ( info_frontline.HasKey( "spectrepoint" ) && info_frontline.kv.spectrepoint == "1" )
		{
			spectreNodeArray.append( info_frontline )
			continue
		}
		// group them based on group name
		local group = "temp_group"
		if ( info_frontline.HasKey( "group" ) )
			group = info_frontline.Get( "group" )
		local side = info_frontline.GetTeam()	//	0 or 1

		if ( !( group in file.frontlineGroupTable ) )
			file.frontlineGroupTable[ group ] <- CreateFrontlineTable()

		file.frontlineGroupTable[ group ].name = group

		if ( file.debug & DEBUG_FRONTLINE_ENTS )
			DebugDrawText( info_frontline.GetOrigin(), "o", false, 10 )

		file.frontlineGroupTable[ group ].sideNodeArray[ side ].append( info_frontline )
	}

	// calculate frontline center and direction
	foreach( group, frontlineTable in file.frontlineGroupTable )
	{
		Assert( frontlineTable.sideNodeArray[0].len() == 3, "Frontline group [" + group + "] does not have 3 info_frontline ents for side #0" )
		Assert( frontlineTable.sideNodeArray[1].len() == 3, "Frontline group [" + group + "] does not have 3 info_frontline ents for side #1" )

		frontlineTable.frontlineCenter = GetFrontlineCenter( frontlineTable )
		frontlineTable.frontlineVector = GetFrontlineVector( frontlineTable )

		frontlineTable.width = GetFrontlineWidth( frontlineTable )

		frontlineTable.combatDir = Vector( frontlineTable.frontlineVector.y, -frontlineTable.frontlineVector.x, 0 )

		if ( file.debug & DEBUG_FRONTLINE_ENTS )
		{
			// debug stuff
			local o = frontlineTable.frontlineCenter
			local v = frontlineTable.frontlineVector
			local dir = Vector( v.y, -v.x, 0 )	// vector pointing away from side 0 towards side 1
			DebugDrawLine( o, o + v * 1000, 0, 0, 255, true, 10 )
			DebugDrawLine( o, o + v * -1000, 0, 0, 128, true, 10 )
			DebugDrawLine( o, o + dir * 1000, 255,0, 0, true, 10 )
			DebugDrawLine( o, o + dir * -1000, 128, 0, 0, true, 10 )

			DebugDrawText( frontlineTable.frontlineCenter, group, false, 10 )
		}
	}

	// pair up spectre frontline nodes with it's closest regular frontline node
	foreach( spectreNode in spectreNodeArray )
	{
		local group = spectreNode.kv.group
		local side = spectreNode.GetTeam()
		local nearestDist = null
		local nearestNode = null
		Assert( group in file.frontlineGroupTable )

		foreach( frontlineNode in file.frontlineGroupTable[ group ]["sideNodeArray"][ side ] )
		{
			local dist = Distance( spectreNode.GetOrigin(), frontlineNode.GetOrigin() )
			if ( nearestDist == null || dist < nearestDist )
			{
				if ( "spectreNode" in frontlineNode.s )
					continue

				nearestDist = dist
				nearestNode = frontlineNode
			}
		}

		Assert( nearestNode, "couldn't find a frontline node to for frontline spectre node at " +  spectreNode.GetOrigin() )
		nearestNode.s.spectreNode <- spectreNode
	}
}

//////////////////////////////////////////////////////////
function CreateFrontlineTable()
{
	local frontlineTable = {}

	frontlineTable.sideNodeArray	<- [ [], [] ]	// two arrays for side 0 and side 1
	frontlineTable.frontlineCenter	<- null
	frontlineTable.frontlineVector	<- null
	frontlineTable.combatDir		<- null
	frontlineTable.width			<- null
	frontlineTable.lineDistFrac		<- 0
	frontlineTable.useCount			<- 0
	frontlineTable.name				<- ""

	return frontlineTable
}

//////////////////////////////////////////////////////////
function CheckFrontlineOverrun( losingTeam )
{
	// the frontline is overrun when there are more enemies then friendlies on the dead players side of the line.
	// losingTeam is the team of the player that died.

	// don't move frontline after the match is won.
	if ( GetGameState() >= eGameState.WinnerDetermined )
		return

	local otherTeam

	switch (losingTeam)
	{
		case TEAM_IMC:
		{
			otherTeam = TEAM_MILITIA
			break
		}
		case TEAM_MILITIA:
		{
			otherTeam = TEAM_IMC
			break
		}
		default:
		{
			// FIX: Exit if the dying entity is neutral/unassigned
			return 
		}
	}
    
	local teamScore = [ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 ]
	local frontline = file.currentFrontline
	local center = frontline.frontlineCenter
	local combatDir = GetTeamCombatDir( frontline, otherTeam )
	local playerArray = GetLivingPlayers()
	local rest = 0

	foreach( player in playerArray )
	{
		local team = player.GetTeam()
		local offsetCenter = team == losingTeam ? center - combatDir * 512 : center

		if ( IsPointInFrontofLine( player.GetOrigin(), offsetCenter, combatDir ) )
		{
			teamScore[ team ] += 1.0
		}
		else
		{
			// player on the other side of the line
			rest++
		}
	}

	if ( rest > ( playerArray.len() / 2.0 ) )
		return	// more players on the other side of the line.

	if ( teamScore[ losingTeam ] < teamScore[ otherTeam ] )
	{
		local prevFrontlineName = file.currentFrontline.name

		MoveFrontline( otherTeam )

		if ( file.debug & DEBUG_FRONTLINE_SWITCHED )
		{
			local teamStr = ( otherTeam == TEAM_IMC ) ? "IMC" : "Militia"
			printt( teamStr, "forced a Frontline switch" )
			printt( prevFrontlineName, " --> ", file.currentFrontline.name )
			printt( format( "%2.1f points vs %2.1f points. A total of %d living Players.", teamScore[ otherTeam ], teamScore[ losingTeam ] , playerArray.len() ) )
		}
	}
}

//////////////////////////////////////////////////////////
function MoveFrontline( winningTeam )
{
	if ( GameRules.GetGameMode() == CAPTURE_THE_FLAG )
		return

	local prevFrontlineName = file.currentFrontline.name

	// switch to different frontline
	file.currentFrontline = GetBestFrontline( winningTeam )
	file.currentFrontline.useCount++
	file.nextOverrunCheck = Time() + FRONTLINE_MIN_TIME

	DebugSendClientFrontlineAllPlayers()

	// determine what sides of the new fronline belong to what team
	SetFrontlineSides( file.currentFrontline, winningTeam )

	// reset the KPS stuff
	ResetFrontlineKillsPerSecond()

	// gather all squads and have them assault the new fronline
	for ( local squadIndex = 0; squadIndex < level.aiSquadCount; squadIndex++ )
	{
		local squadName = MakeSquadName( TEAM_IMC, squadIndex )
		local squadSize = GetNPCSquadSize( squadName )
		if ( squadSize )
		{
			local squad = GetNPCArrayBySquad( squadName )
			SquadAssaultFrontline( squad, squadIndex )
		}

		squadName = MakeSquadName( TEAM_MILITIA, squadIndex )
		squadSize = GetNPCSquadSize( squadName )
		if ( squadSize )
		{
			local squad = GetNPCArrayBySquad( squadName )
			SquadAssaultFrontline( squad, squadIndex )
		}
	}
}

//////////////////////////////////////////////////////////
function GetCurrentFrontline()
{
	if ( !Flag( "FrontlineInitiated" ) )
		return null

	return file.currentFrontline
}

//////////////////////////////////////////////////////////
function GetTeamCombatDir( frontline, team )
{
	// combatDir points towards side 1 by default
	// if the team belongs to side 1 we need to reverse the direction
	local combatDir = frontline.combatDir
	if ( file.frontlineTeamSide[ team ] == 1 )
		combatDir *= -1	// make sure combatDir is heading away from the team side, combatDir points towards side 1 by default.
	return combatDir
}

//////////////////////////////////////////////////////////
function GetBestFrontline( winningTeam )
{
	/*
		will look for frontlines in the winning teams combat direction.
		if none is found it will look 45 degrees to the right then 45 degrees to the left and finally opposite to the combat direction.
		with a fov (minDot) of 67.5 degree every direction will be covered, so it should always return a frontline.
	*/

	local combatDir = GetTeamCombatDir( file.currentFrontline, winningTeam )

	local right = CalcRelativeVector( Vector( 0,45,0), combatDir )
	local left = CalcRelativeVector( Vector( 0,-45,0), combatDir )
	local rear = combatDir * -1
	local vectorArray = [ combatDir, right, left, rear ]

	foreach( index, vector in vectorArray )
	{
		//DebugDrawLine( file.currentFrontline.frontlineCenter, file.currentFrontline.frontlineCenter + vector * 5000, 0, 255, 0, true, 2 )
		local frontline = FindFrontlineInDirection( vector )
		if ( frontline )
		{
			//printt( "Found frontline using index: ", index )
			return frontline
		}
	}

	// fallback in case no new frontline was found. Happens in map that only have one.
	return file.currentFrontline
}

//////////////////////////////////////////////////////////
function FindFrontlineInDirection( forwardVector )
{
	local currentCenter = file.currentFrontline.frontlineCenter
	local maxDist = 5000
	local graceRange = 768
	local minDot = 0.38		// about 67.5 degrees.
	local forwardFrontline = null
	local leastUsed
	local closestDistFrac = 1
	local frontlineSelection = []

	foreach( groupName, frontline in file.frontlineGroupTable )
	{
		frontline.lineDistFrac = 0

		if ( frontline == file.currentFrontline )
			continue

		local vector = frontline.frontlineCenter - currentCenter
		local dist = vector.Norm()
		local dot = forwardVector.Dot( vector )	// positive is infront of the line

		if ( dot > minDot && dist < maxDist )
		{
			//DebugDrawLine( currentCenter, frontline.frontlineCenter, 255, 255, 0, true, 2 )
			//DebugDrawText( frontline.frontlineCenter + Vector(0,0,200), "Dot: " + dot.tostring() + " Dist: " + dist.tostring(), false, 2 )

			local lineTable = CalcClosestPointOnLine( frontline.frontlineCenter, currentCenter, currentCenter + forwardVector * maxDist )
			Assert( lineTable.t > 0 )

			frontline.lineDistFrac = lineTable.t
			frontlineSelection.append( frontline )

			if ( lineTable.t < closestDistFrac )
			{
				closestDistFrac = lineTable.t
				leastUsed = frontline.useCount
				forwardFrontline = frontline
			}
		}
	}

	if ( !forwardFrontline )
		return false

	// find any frontlines withing graceRange of the closest frontline and select the least used.
	foreach( frontline in frontlineSelection )
	{
		if ( frontline == file.currentFrontline )
			continue

		local distDif = ( frontline.lineDistFrac - closestDistFrac ) * maxDist
		if ( abs( distDif ) > graceRange )
			continue

		if ( frontline.useCount < leastUsed )
		{
			forwardFrontline = frontline
			leastUsed = frontline.useCount
		}
	}

	Assert( forwardFrontline )
	return forwardFrontline
}

//////////////////////////////////////////////////////////
function GetFrontlineCenter( frontlineTable )
{
	local entArray = clone frontlineTable.sideNodeArray[0]
	Assert( entArray.len() )

	entArray.extend( frontlineTable.sideNodeArray[1] )

	local centerPos = Vector( 0,0,0 )
	foreach( ent in entArray )
		centerPos += ent.GetOrigin()

	centerPos *= ( 1.0 / entArray.len() )
	return centerPos
}

//////////////////////////////////////////////////////////
function GetFrontlineVector( frontlineTable )
{
	local centerPos0 = Vector( 0,0,0 )
	foreach( ent in frontlineTable.sideNodeArray[0] )
		centerPos0 += ent.GetOrigin()

	local centerPos1 = Vector( 0,0,0 )
	foreach( ent in frontlineTable.sideNodeArray[1] )
		centerPos1 += ent.GetOrigin()

	centerPos0 *= ( 1.0 / frontlineTable.sideNodeArray[0].len() )
	centerPos1 *= ( 1.0 / frontlineTable.sideNodeArray[1].len() )

	local vector = centerPos1 - centerPos0
	vector.Norm()

	// return the left vector
	return Vector( -vector.y, vector.x, 0 )
}

function GetFrontlineWidth( frontlineTable )
{
	local highDist = 0
	for ( local side = 0; side < 2; side++ )
	{
		local nodeArray = frontlineTable.sideNodeArray[ side ]
		foreach ( baseNode in nodeArray )
		{
			foreach ( node in nodeArray )
			{
				local dist = Distance( baseNode.GetOrigin(), node.GetOrigin() )
				if ( dist > highDist )
					highDist = dist
			}
		}
	}

	printt( frontlineTable.name, frontlineTable, highDist )
	local width = ( highDist * 0.5 ) + 512
	return width	// half the width since all calculations are based on the center of the frontline
}

// Temporary - backup stuff incase a map doesn't have info_frontline ents
function CreateTempFrontline()
{
	printt( "************************************" )
	printt( "Map doesn't have info_frontline ents" )
	printt( "************************************" )

	local spawnpoints = SpawnPoints_GetPilotStart( TEAM_ANY )
	if ( GameRules.GetGameMode() == LAST_TITAN_STANDING || GameRules.GetGameMode() == WINGMAN_LAST_TITAN_STANDING )
		spawnpoints = SpawnPoints_GetTitanStart( TEAM_ANY )

	if ( spawnpoints.len() == 0 )
		return []

	local originArray = []
	local mapCenter = GetMapCenter( spawnpoints )
	local mapDir = GetMapDirection( mapCenter, spawnpoints )	//	vector points away from the IMC side
	local leftDir = Vector( -mapDir.y, mapDir.x, 0 )

	local flankDist = 1024
	leftDir *= flankDist

	originArray.append( mapCenter )
	originArray.append( mapCenter + leftDir )
	originArray.append( mapCenter - leftDir )

	local entArray = []
	foreach( origin in originArray )
	{
		local info_frontline = CreateEntity( "info_frontline" )
		info_frontline.kv.group = "tempgroups"	// doesn't work
		info_frontline.kv.TeamNum = 0
		info_frontline.SetOrigin( origin + ( mapDir * 512 ) )
		DispatchSpawn( info_frontline )
		entArray.append( info_frontline )
	}

	foreach( origin in originArray )
	{
		local info_frontline = CreateEntity( "info_frontline" )
		info_frontline.kv.group = "temp_group"	// doesn't work
		info_frontline.kv.TeamNum = 1
		info_frontline.SetOrigin( origin + ( mapDir * -512 ) )
		DispatchSpawn( info_frontline )
		entArray.append( info_frontline )
	}

	return entArray
}

//////////////////////////////////////////////////////////
function GetMapCenter( spawnpoints )
{
	local centerPos = Vector( 0, 0, 0 )
	foreach ( spawnpoint in spawnpoints )
		centerPos += spawnpoint.GetOrigin()
	centerPos *= ( 1.0 / spawnpoints.len() )

	return centerPos
}

//////////////////////////////////////////////////////////
function GetMapDirection( centerPos, startSpawnPoints )
{
	if ( startSpawnPoints.len() == 0 )
		return Vector( 1, 0, 0 )

	local imcCount = 0
	local militiaCount = 0
	local imcCenter = Vector( 0, 0, 0 )
	local militiaCenter = Vector( 0, 0, 0 )
	local dirToIMC = Vector( 1, 0, 0 )
	local dirFromMilitia = Vector( 1, 0, 0 )

	foreach ( startSpawn in startSpawnPoints )
	{
		if ( startSpawn.GetTeam() == TEAM_IMC )
		{
			imcCenter += startSpawn.GetOrigin()
			imcCount++
		}
		else if ( startSpawn.GetTeam() == TEAM_MILITIA )
		{
			militiaCenter += startSpawn.GetOrigin()
			militiaCount++
		}
	}

	if ( imcCount > 0 )
	{
		imcCenter *= 1.0 / imcCount.tofloat()
		dirToIMC = imcCenter - centerPos
		dirToIMC.Normalize()
	}

	if ( militiaCount > 0 )
	{
		militiaCenter *= 1.0 / militiaCount.tofloat()
		dirFromMilitia = centerPos - militiaCenter	// reverse of dirToIMC
		dirFromMilitia.Normalize()
	}

	local mapDir = ( dirFromMilitia + dirToIMC ) * 0.5
	return mapDir	//	vector points away from the IMC side
}


//////////////////////////////////////////////////////////
function SetFrontlineSides( frontline, winningTeam )
{
	local otherTeam

	switch (winningTeam)
	{
		case TEAM_IMC:
		{
			otherTeam = TEAM_MILITIA
			break
		}
		case TEAM_MILITIA:
		{
			otherTeam = TEAM_IMC
			break
		}
	}
	local center = frontline.frontlineCenter

	// combatDir is towards side 1, away from side 0
	local combatDir = file.currentFrontline.combatDir

	local playerArray = GetLivingPlayers()

	// for the start of the map when no players are avaliable
	if ( GetGameState() <= eGameState.Prematch || GetGameState() == eGameState.SwitchingSides || playerArray.len() == 0 )
		playerArray = GetEntArrayByClass_Expensive( "info_spawnpoint_human_start" )

	local teamCount = [ 0, 0 ]
	foreach ( player in playerArray )
	{
		if ( IsPlayer( player ) && player.GetDoomedState() )
			continue

		if ( IsPointInFrontofLine( player.GetOrigin(), center, combatDir ) )
		{
			if ( player.GetTeam() == winningTeam )
				teamCount[ 1 ]++
		}
		else
		{
			if ( player.GetTeam() == winningTeam )
				teamCount[ 0 ]++
		}

		if ( file.debug & DEBUG_FRONTLINE_SELECTED )
			DebugDrawText( player.GetOrigin(), ".xX " + player.GetTeam() + " Xx.", false, 10 )
	}

	if ( teamCount[ 1 ] > teamCount[ 0 ] )
	{
		file.frontlineTeamSide[ winningTeam ]	= 1
		file.frontlineTeamSide[ otherTeam ]		= 0
	}
	else
	{
		file.frontlineTeamSide[ otherTeam ]		= 1
		file.frontlineTeamSide[ winningTeam ]	= 0
	}

	if ( file.debug & DEBUG_FRONTLINE_SELECTED )
	{
		local vector = frontline.frontlineVector
		local combatDir = file.currentFrontline.combatDir	// towards side 1

		DebugDrawLine( center, center + vector * 1000, 0, 0, 255, true, 10 )
		DebugDrawLine( center, center + vector * -1000, 0, 0, 128, true, 10 )
		DebugDrawLine( center + Vector( 0,0,32 ), center + combatDir * 512, 255, 255, 255, true, 10 )
		DebugDrawLine( center + Vector( 0,0,32 ), center + Vector( 0,0,128), 255, 255, 255, true, 10 )
		DebugDrawText( center, frontline.name + " " + frontline.useCount, false, 10 )

		local teamStr = "MILITIA - " + teamCount[ 1 ] + " vs " + teamCount[ 0 ]
		if ( file.frontlineTeamSide[ TEAM_IMC ] == 1 )
			teamStr = "IMC - " + teamCount[ 1 ] + " vs " + teamCount[ 0 ]
		DebugDrawText( center + combatDir * 512, teamStr, false, 10 )
	}
}

//////////////////////////////////////////////////////////
function RateFrontLineNPCSpawnpoint( spawnpoint, team, edgeOrigin, combatDir )
{
	local frontlineRating = 0

	local testPoint = spawnpoint.GetOrigin()

	local infront = IsPointInFrontofLine( testPoint, edgeOrigin, combatDir )

	if ( !infront )
	{
		local distSqr = Distance2DSqr( testPoint, edgeOrigin )
		frontlineRating = GraphCapped( distSqr, FRONTLINE_MIN_DIST_SQR, FRONTLINE_MAX_DIST_SQR, 1.0, 0.0 )
	}
	else
	{
		frontlineRating = -100	// these are on the wrong side of the frontline so make them real bad to use
	}

	frontlineRating	*= 2.0

	spawnpoint.CalculateRating( TD_AI, team, frontlineRating, frontlineRating )

/*
	if ( file.debug & DEBUG_NPC_SPAWN )
	{
		// debug
		local textStr = format( ".xX%dXx.", spawnpoint.GetEntIndex() )
		if ( rating > -50 )
			textStr = format( "%d | %2.2f | %2.2f", spawnpoint.GetEntIndex(), frontlineRating, rating )

		DebugDrawText( testPoint + Vector(0,0,64), textStr, false, 10 )
	}
*/
}


//////////////////////////////////////////////////////////
function FrontlineDeathNPC( ent, damageInfo )
{
	FrontlineDeath( ent, damageInfo )
}

//////////////////////////////////////////////////////////
function FrontlineDeath( ent, damageInfo )
{
	if ( ent.IsTitan() && !ent.GetTitanSoul().GetBossPlayer() )
		return	// don't care about npc_titans that wasn't controlled by a player

	if ( ent.IsNPC() && !ent.IsTitan() )
	{
		// don't check if we recently moved the frontline
		local time = Time()
		if ( file.nextOverrunCheck > time )
			return

		file.nextOverrunCheck = Time() + 1
	}

	local team = ent.GetTeam()
	CheckFrontlineOverrun( team )
}

//////////////////////////////////////////////////////////
function GetFrontlineNPCKillsPerSec( team )
{
	// returns the number of dead npc in the last [KPS_TIMEFRAME] seconds
	local newArray = []
	foreach( timestamp in file.npcDeathPerTeam[ team ] )
	{
		if ( timestamp > Time() - KPS_TIMEFRAME )
			newArray.append( timestamp )
	}

	file.npcDeathPerTeam[ team ] = newArray

	return newArray.len() / KPS_TIMEFRAME.tofloat()
}

//////////////////////////////////////////////////////////
function GetFrontlinePlayerKillsPerSec( team )
{
	// returns the number of dead players in the last [PLAYER_KPS_TIMEFRAME] seconds
	local newArray = []
	foreach( timestamp in file.playerDeathPerTeam[ team ] )
	{
		if ( timestamp > Time() - PLAYER_KPS_TIMEFRAME )
			newArray.append( timestamp )
	}

	file.playerDeathPerTeam[ team ] = newArray

	return newArray.len() / PLAYER_KPS_TIMEFRAME.tofloat()
}

//////////////////////////////////////////////////////////
function ResetFrontlineKillsPerSecond()
{
	file.npcDeathPerTeam[ TEAM_IMC ] = []
	file.npcDeathPerTeam[ TEAM_MILITIA ] = []
	file.playerDeathPerTeam[ TEAM_IMC ] = []
	file.playerDeathPerTeam[ TEAM_MILITIA ] = []

}

//////////////////////////////////////////////////////////
function GetFrontlineGoal( index, team, spectre = false )
{
	local frontline = file.currentFrontline
	local side = file.frontlineTeamSide[ team ]
	local nodeArray = frontline.sideNodeArray[ side ]
	Assert( nodeArray.len() == 3 )

	local node = nodeArray[ index % 3 ]
	if ( spectre && "spectreNode" in node.s )
		node = node.s.spectreNode

	return node
}

//////////////////////////////////////////////////////////
function SquadAssaultFrontline( squad, squadIndex )
{
//	This was a version that created assault_assaultpoints so that I could tweek settings. Rather not use it.
	SquadAssaultFrontline_AssaultEnts( squad, squadIndex )
	//SquadAssaultFrontline_Old( squad )
}

//////////////////////////////////////////////////////////
function GetAdditionalNodesForNotEnoughCoverNodes( goalNodes, nearestNode, squadSize )
{
	// get enough nodes incase there are duplicates in neighborNodes and goalNodes
	local neighborNodes = GetNeighborNodes( nearestNode, squadSize + goalNodes.len(), HULL_HUMAN )
	foreach( i, node in neighborNodes )
	{
		if ( !( node in goalNodes ) )
		{
			goalNodes.append( node )
			if ( goalNodes.len() == squadSize )
				break
		}
	}
}
Globalize( GetAdditionalNodesForNotEnoughCoverNodes )

function GetAdditionalNodesForNotEnoughCoverNodesWithinHeight( goalNodes, nearestNode, squadSize, height, heightCheck )
{
	// get enough nodes incase there are duplicates in neighborNodes and goalNodes
	local neighborNodes = GetNeighborNodes( nearestNode, squadSize + goalNodes.len(), HULL_HUMAN )
	foreach( i, node in neighborNodes )
	{
		if ( !( node in goalNodes ) )
		{
			local pos = GetNodePos( node, HULL_HUMAN )
			if ( fabs( pos.z - height ) > heightCheck )
				continue

			goalNodes.append( node )
			if ( goalNodes.len() == squadSize )
				break
		}
	}
}
Globalize( GetAdditionalNodesForNotEnoughCoverNodesWithinHeight )

//////////////////////////////////////////////////////////
function SquadAssaultFrontline_AssaultEnts( squad, squadIndex )
{
	Assert( squadIndex != null )

	if ( !Flag( "FrontlineInitiated" ) )
		return

	if(!squad)	// 스쿼드가 없으면 스킵환다.
		return

	// Guys in squad can die at any time - it seems bad that this can be the case, squad should be clean earlier if at all
	ArrayRemoveInvalid( squad )

	local squadSize = squad.len()
	if ( squadSize == 0 )
		return

	local isSpectre = squad[0].IsSpectre()
	local team = squad[0].GetTeam()
	local goal = GetFrontlineGoal( squadIndex, team, isSpectre )
	Assert( goal != null )

	local frontline = file.currentFrontline
	local combatDir = GetTeamCombatDir( frontline, team )

	local nearestNode = GetNearestNodeToPos( goal.GetOrigin() )
	if ( nearestNode < 0 )
	{
		printl( "Error: No path nodes near droppod spawn point at " + goal.GetOrigin() )
		return
	}

	local goalNodes = GetNearbyCoverNodes( nearestNode, squad.len(), HULL_HUMAN, isSpectre, 400, combatDir.GetAngles().y, 90 )

	// Debug lines
	if ( GetBugReproNum() == 1234 )
	{
		local pos = GetNodePos( nearestNode, HULL_HUMAN )
		DebugDrawLine( pos, pos + combatDir * 512, 0, 255, 255, true, 30 )

		foreach( node in goalNodes )
			DebugDrawLine( GetNodePos( node, HULL_HUMAN ), GetNodePos( node, HULL_HUMAN ) + Vector( 0,0,128 ), 0, 255, 0, true, 30 )
	}

	// fill up rest with regular nodes
	if ( goalNodes.len() < squadSize )
	{
		GetAdditionalNodesForNotEnoughCoverNodes( goalNodes, nearestNode, squadSize )

		// Debug lines
		if ( GetBugReproNum() == 1234 )
		{
			foreach( node in goalNodes )
				DebugDrawLine( GetNodePos( node, HULL_HUMAN ), GetNodePos( node, HULL_HUMAN ) + Vector( 0,0,64 ), 255, 0, 0, true, 30 )
		}
	}


	foreach ( i, node in goalNodes )
	{
		local nodePos = GetNodePos( node, HULL_HUMAN )
		local npc = squad[ i ]

		Assert( "assaultPoint" in npc.s )
		SetFrontlineAssaultPointValues( npc.s.assaultPoint )
		npc.s.assaultPoint.SetOrigin( nodePos )

		if ( file.debug & DEBUG_ASSAULTPOINT )
		{
			//DebugDrawText( nodePos, "AP", false, 10 )
			thread DrawAssaultGoal( squad[ i ], nodePos )
		}

		squad[ i ].AssaultPointEnt( npc.s.assaultPoint )
		squad[ i ].StayPut( true )
	}
}

//////////////////////////////////////////////////////////
function SetFrontlineAssaultPointValues( point )
{
	point.kv.stopToFightEnemyRadius = 800
	point.kv.allowdiversionradius = 0
	point.kv.allowdiversion = 1
	point.kv.faceAssaultPointAngles = 0
	point.kv.assaulttolerance = 512
	point.kv.nevertimeout = 0
	point.kv.strict = 0
	point.kv.forcecrouch = 0
	point.kv.spawnflags = 0
	point.kv.clearoncontact = 1
	point.kv.assaulttimeout = RandomFloat( 4, 8 )
	point.kv.arrivaltolerance = 600
}

//////////////////////////////////////////////////////////
function SquadAssaultFrontline_Old( squad, squadIndex )
{
	Assert( squadIndex != null )

	if ( !Flag( "FrontlineInitiated" ) )
		return

	if ( squad.len() > 1 )
	{
		local team = squad[0].GetTeam()
		local goal = GetFrontlineGoal( squadIndex, team )
		Assert( goal != null )

		SquadAssault( squad, goal.GetOrigin() )
	}
}


//////////////////////////////////////////////////////////
function SquadAssault( squad, pos )
{
	local nearestNode = GetNearestNodeToPos( pos )
	if ( nearestNode < 0 )
	{
		printl( "Error: No path nodes near droppod spawn point at " + pos )
		return
	}

	// Guys in squad can die at any time
	ArrayRemoveInvalid( squad )

	local squadSize = squad.len()
	if ( squadSize == 0 )
		return

	local isSpectre = squad[0].IsSpectre()

	// need a direction passed in here
	local goalNodes = GetNearbyCoverNodes( nearestNode, squad.len(), HULL_HUMAN, isSpectre, 400, 0, 180 )

	// fill up rest with regular nodes
	if ( goalNodes.len() < squadSize )
		GetAdditionalNodesForNotEnoughCoverNodes( goalNodes, nearestNode, squadSize )

	foreach ( i, node in goalNodes )
	{
		local nodePos = GetNodePos( node, HULL_HUMAN )
		squad[ i ].AssaultPoint( nodePos )
		squad[ i ].StayPut( true )

		if ( file.debug & DEBUG_ASSAULTPOINT )
			thread DrawAssaultGoal( squad[ i ], nodePos )
	}
}


// debug functions
function DebugSendClientFrontline( player )
{
	if ( developer() == 0 )
		return

	if ( "currentFrontline" in file && file.currentFrontline != null )
	{
		local center = file.currentFrontline.frontlineCenter
		local dir = GetTeamCombatDir( file.currentFrontline, TEAM_IMC )
		Remote.CallFunction_Replay( player, "DebugSetFrontline", center.x, center.y, center.z, dir.x, dir.y );
	}
}

function DebugSendClientFrontlineAllPlayers()
{
	if ( developer() == 0 )
		return

	local center = file.currentFrontline.frontlineCenter
	local dir = GetTeamCombatDir( file.currentFrontline, TEAM_IMC )
	local playerArray = GetPlayerArray()
	foreach( player in playerArray )
		Remote.CallFunction_Replay( player, "DebugSetFrontline", center.x, center.y, center.z, dir.x, dir.y )
}

function DebugSquad()
{
	local npcArray = GetNPCArrayByClass( "npc_soldier" )
	foreach( npc in npcArray )
		thread DebugSquadThread( npc )
}

function DebugSquadThread( npc )
{
	if ( !IsAlive( npc ) )
		return

	npc.Signal( "EndDebugSquadIndex" )
	npc.EndSignal( "EndDebugSquadIndex" )

	while( IsAlive( npc ) )
	{
		DebugDrawText( npc.GetOrigin() + Vector(0,0,64), npc.kv.squadname, false, 0.5 )
		wait 0.5
	}
}

function DebugNextFrontline()
{
	file.currentFrontline.useCount++

	local useCount = file.currentFrontline.useCount
	local selectedFrontline

	foreach( frontline in file.frontlineGroupTable )
	{
		if ( frontline.useCount <= useCount )
		{
			useCount = frontline.useCount
			selectedFrontline = frontline
		}
	}

	file.currentFrontline = selectedFrontline
	SetFrontlineSides( file.currentFrontline, TEAM_IMC )

	// gather all squads and have them assault the new fronline
	for ( local squadIndex = 0; squadIndex < level.aiSquadCount; squadIndex++ )
	{
		local squadName = MakeSquadName( TEAM_IMC, squadIndex )
		local squadSize = GetNPCSquadSize( squadName )
		if ( squadSize )
		{
			local squad = GetNPCArrayBySquad( squadName )
			SquadAssaultFrontline( squad, squadIndex )
		}

		squadName = MakeSquadName( TEAM_MILITIA, squadIndex )
		squadSize = GetNPCSquadSize( squadName )
		if ( squadSize )
		{
			local squad = GetNPCArrayBySquad( squadName )
			SquadAssaultFrontline( squad, squadIndex )
		}
	}

	DebugSendClientFrontlineAllPlayers()
}

function DrawMapCenter()
{
	local ents = SpawnPoints_GetDropPodStart( TEAM_ANY )
	local mapCenter = GetMapCenter( ents )

	foreach ( ent in ents )
		DebugDrawLine( ent.GetOrigin(), mapCenter, 128, 128, 128, true, 10 )
	DebugDrawText( mapCenter, "MAP CENTER", false, 10 )
}

function DebugDrawFrontLineSpawn()
{
	if ( "drawFrontlineSpawn" in file )
		delete file.drawFrontlineSpawn
	else
		file.drawFrontlineSpawn <- true

	if ( !( "spawnpoints" in file ) )
	{
		file.spawnpoints <- GetEntArrayByClass_Expensive( "info_spawnpoint_human" )
		file.spawnpoints.extend( GetEntArrayByClass_Expensive( "info_spawnpoint_titan" ) )
	}
}

function DrawCurrentFrontline()
{
	thread DrawCurrentFrontline_thread()
}

function DrawCurrentFrontline_thread()
{
	if ( "drawCurrentFrontline" in file )
	{
		delete file.drawCurrentFrontline
		return
	}

	file.drawCurrentFrontline <- true
	while( "drawCurrentFrontline" in file )
	{
		if ( "drawFrontlineSpawn" in file )
		{
			DebugDrawFrontlineSpawnBox( file.currentFrontline, TEAM_IMC, { r=64, g=64, b=255 } )
			DebugDrawFrontlineSpawnBox( file.currentFrontline, TEAM_MILITIA, { r=96, g=255, b=96 } )
		}

		DrawFrontline( file.currentFrontline )
		wait 0.5
	}
}

function DebugDrawFrontlineSpawnBox( frontline, team, color )
{
	local spawnDir = GetTeamCombatDir( frontline, team ) * -1
	local offsetOrigin = frontline.frontlineCenter + spawnDir * FRONTLINE_PLAYER_SPAWN_OFFSET
	local midRange = FRONTLINE_PLAYER_SPAWN_DIST
	local maxRange = FRONTLINE_PLAYER_SPAWN_DIST * 3

	local left = offsetOrigin + frontline.frontlineVector * frontline.width
	local right = offsetOrigin + frontline.frontlineVector * -frontline.width
	local midOffset = spawnDir * midRange
	local maxOffset = spawnDir * maxRange

	DebugDrawLine( left, right, color.r, color.g, color.b, true, 0.5 )
	DebugDrawLine( left, left + maxOffset, color.r, color.g, color.b, true, 0.5 )
	DebugDrawLine( right, right + maxOffset, color.r, color.g, color.b, true, 0.5 )
	DebugDrawLine( left + maxOffset, right + maxOffset, color.r, color.g, color.b, true, 0.5 )
	DebugDrawLine( left + midOffset, right + midOffset, 255, 96, 96, true, 0.5 )
	DebugDrawText( offsetOrigin + midOffset, "Optimal distance", false, 0.5 )

	DebugDrawSpawnpoints( frontline, offsetOrigin, spawnDir, maxRange, color )
}

function DebugDrawSpawnpoints( frontline, origin, spawnDir, length, color )
{
	local badColor = { r = 96, g = 0, b = 0 }
	local drawColor

	foreach( spawnpoint in file.spawnpoints )
	{
		local spawnOrigin = spawnpoint.GetOrigin()
		local spawnAngles = spawnpoint.GetAngles()

		local spawnVector = spawnOrigin - origin
		local forwardDist = spawnDir.Dot( spawnVector )
		local sideDist = fabs( frontline.frontlineVector.Dot( spawnVector ) )

		if ( forwardDist > 0 && forwardDist < length &&  sideDist < frontline.width )
		{
			local vector = spawnOrigin - frontline.frontlineCenter
			local facing = spawnpoint.GetForwardVector()
			if ( vector.Dot( facing ) > 0 )
				drawColor = badColor
			else
				drawColor = color

			if ( spawnpoint.GetClassname() == "info_spawnpoint_human" )
				DrawLineBox( spawnOrigin, spawnAngles, Vector( 16, 16, 72 ), drawColor.r, drawColor.g, drawColor.b, 0.5 )
			else
				DrawLineBox( spawnOrigin, spawnAngles, Vector( 64, 64, 256 ), drawColor.r, drawColor.g, drawColor.b, 0.5 )
		}
	}
}

function DrawLineBox( origin, angles, size, r, g, b, time )
{
	local fVector = angles.AnglesToForward()
	local rVector = angles.AnglesToRight()

	local lfr  = origin + ( fVector * size.x ) + ( rVector * size.y )
	local lfl  = origin + ( fVector * size.x ) + ( rVector * -size.y )
	local lrr  = origin + ( fVector * -size.x ) + ( rVector * size.y )
	local lrl  = origin + ( fVector * -size.x ) + ( rVector * -size.y )

	local ufr  = lfr + Vector( 0, 0, size.z )
	local ufl  = lfl + Vector( 0, 0, size.z )
	local urr  = lrr + Vector( 0, 0, size.z )
	local url  = lrl + Vector( 0, 0, size.z )

	local dirStart = origin + Vector( 0, 0, size.z * 0.5 )
	local dirEnd = origin + fVector * ( size.x * 2 ) + Vector( 0, 0, size.z * 0.5 )

	DebugDrawLine( dirStart, dirEnd  , r, g, b, true, time )

	DebugDrawLine( lfr, lfl, r, g, b, true, time )
	DebugDrawLine( lfl, lrl, r, g, b, true, time )
	DebugDrawLine( lrl, lrr, r, g, b, true, time )
	DebugDrawLine( lrr, lfr, r, g, b, true, time )

	DebugDrawLine( lfr, ufr, r, g, b, true, time )
	DebugDrawLine( lfl, ufl, r, g, b, true, time )
	DebugDrawLine( lrl, url, r, g, b, true, time )
	DebugDrawLine( lrr, urr, r, g, b, true, time )

	DebugDrawLine( ufr, ufl, r, g, b, true, time )
	DebugDrawLine( ufl, url, r, g, b, true, time )
	DebugDrawLine( url, urr, r, g, b, true, time )
	DebugDrawLine( urr, ufr, r, g, b, true, time )
}

function DebugDrawFrontLine()
{
	thread DebugDrawFrontLine_thread()
}

function DebugDrawFrontLine_thread()
{
	if ( "drawFrontline" in file )
	{
		delete file.drawFrontline
		return
	}

	file.drawFrontline <- true
	while( "drawFrontline" in file )
	{
		foreach( frontline in file.frontlineGroupTable )
			DrawFrontline( frontline )
		wait 0.5
	}
}

function DrawFrontline( frontline )
{
	if ( !Flag( "FrontlineInitiated" ) )
		return

	local player = GetEntByIndex(1)
	if ( !player )
		return

	local team = player.GetTeam()
	local center = frontline.frontlineCenter
	local vector = frontline.frontlineVector
	local combatDir = GetTeamCombatDir( frontline, team )
	local width = frontline.width
	local left = center + vector * width
	local right = center + vector * -width

	DebugDrawLine( center, left, 255, 64, 0, true, 0.5 )
	DebugDrawLine( center, right, 255, 0, 64, true, 0.5 )

	local nameStr = frontline.name + " Used Count: " + frontline.useCount.tostring()
	if ( frontline == file.currentFrontline )
	{
		nameStr += " [CURRENT]"

		DebugDrawLine( center + Vector( 0,0,32 ), center + combatDir * 512, 255, 0, 0, true, 0.5 )
		DebugDrawLine( center + Vector( 0,0,32 ), center + Vector( 0,0,128), 255, 0, 0, true, 0.5 )

		if ( !( "drawFrontlineSpawn" in file ) )
		{
			local teamStr = "MILITIA"
			if ( team == TEAM_IMC )
				teamStr = "IMC"
			DebugDrawText( center + combatDir * 512, teamStr + " Combat Direction", false, 0.5 )
		}
	}
	else
	{
		DebugDrawLine( center + Vector( 0,0,32 ), center + combatDir * 256, 192, 0, 0, true, 0.5 )
		DebugDrawLine( center + Vector( 0,0,32 ), center + combatDir * -256, 192, 0, 0, true, 0.5 )
	}

	DebugDrawText( center, nameStr, false, 0.5 )

	if ( !( "drawFrontlineSpawn" in file )  )
	{
		local frontlineEnts = clone frontline.sideNodeArray[0]
		frontlineEnts.extend( frontline.sideNodeArray[1] )
		foreach( ent in frontlineEnts )
		{
			DebugDrawLine( center, ent.GetOrigin(), 192, 192, 192, true, 0.5 )
			DebugDrawText( ent.GetOrigin(), ent.GetTeam().tostring(), false, 0.5 )
		}
	}
}

RegisterSignal( "DrawAssaultGoal" )
function DrawAssaultGoal( npc, goal )
{
	npc.Signal( "DrawAssaultGoal" )
	npc.EndSignal( "DrawAssaultGoal" )

	while( IsAlive( npc ) )
	{
		DebugDrawLine( npc.GetOrigin(), goal, 128, 128, 128, true, 0.5 )
		wait 0.5
	}
}


function MoveBot( team )
{
	local player = GetEntByIndex( 1 )
	local eyePos = player.EyePosition()
	local vector = player.GetViewVector()

	local bots = GetLivingPlayers( team )
	local trace = TraceLineSimple( eyePos, eyePos + vector * 10000, player )
	local ground = eyePos + vector * ( 10000 * trace )

	local startIndex = file.botIndex[ team ] % bots.len()

	for( local i = startIndex; i < bots.len(); i++ )
	{
		file.botIndex[ team ]++
		if ( bots[ i ].IsBot() )
		{
			bots[ i ].SetOrigin( ground + Vector( 0,0,64 ) )
			break
		}
	}
}




function EntitiesDidLoad()
{
	switch( GameRules.GetGameMode() )
	{
		case CAPTURE_POINT:
			level.AssaultFunc = AssaultHP
			break

		case CAPTURE_THE_FLAG:
			level.AssaultFunc = AssaultCTF
			printt( "[CTF_AI] EntitiesDidLoad CTF branch: CTF_FAKECAP_ENABLED =", CTF_FAKECAP_ENABLED )
			if ( CTF_FAKECAP_ENABLED )
			{
				printt( "[CTF_AI] EntitiesDidLoad: about to spawn fake-cap watchdog thread" )
				thread CTFFakeCaptureWatchdog()
				printt( "[CTF_AI] EntitiesDidLoad: thread call returned" )
			}
			break

		default:
			level.AssaultFunc = AssaultTDM
			break
	}
}


const SQUADSIZE = 4
function ScriptedSquadAssault( squad, index )
{
	Assert( index >= 0 && index <= 2 )
	Assert( squad.len() <= SQUADSIZE, "Squad " + index + " is too big: " + squad.len() )
	level.AssaultFunc( squad, index )
}


//==================================
// FO AI HARDPOINT LOGIC
//==================================
function AssaultHP( guys, index )
{
	if ( !guys.len() )
		return

	local team = guys[ 0 ].GetTeam()
	local squadName = MakeSquadName( team, index )

	foreach ( guy in guys )
	{
		if ( IsValid( guy ) )
			SetSquad( guy, squadName )
	}

	local squad = GetNPCArrayBySquad( squadName )

	if ( squad.len() > SQUADSIZE )
		return

	// Create a 2:1 Attacker/Defender bias based on the squad's index
	local role = ( index < 2 ) ? "attack" : "defend"

	// Route to the dynamic think loop instead of a static order
	thread SquadHardpointRunThink( squadName, team, role )
}

function SquadHardpointRunThink( squadName, team, role )
{
	local signalString = "SquadHardpointRunThink_" + squadName

	level.ent.Signal( signalString )
	level.ent.EndSignal( signalString )

	if ( !GetNPCSquadSize( squadName ) )
		return

	local lastGoal = null

	while ( true )
	{
		local squad = GetNPCArrayBySquad( squadName )
		ArrayRemoveDead( squad )

		if ( !squad.len() )
			return

		// GET THE SQUAD'S CURRENT LOCATION
		// Use the first living member's origin as the reference point
		local squadOrigin = squad[0].GetOrigin()

		// Pass the origin into the new objective function
		local targetHardpoint = GetHardpointObjectiveForTeam( team, role, squadOrigin )

		if ( targetHardpoint != null )
		{
			// Only issue a new assault order if their objective actually changed
			if ( lastGoal == null || targetHardpoint != lastGoal )
			{
				NPCsAssaultHardpoint( squad, targetHardpoint )
				lastGoal = targetHardpoint
			}
		}

		// Wait 3 seconds before re-evaluating the map state
		wait 3.0
	}
}


function GetHardpointObjectiveForTeam( team, role, squadOrigin )
{
	if ( !( "hardpoints" in level ) || level.hardpoints.len() == 0 )
		return null

	local ownedPoints = []
	local neutralPoints = []
	local enemyPoints = []

	local emergencyPoint = null
	local closestEmergencyDist = 99999999

	// Categorize all hardpoints on the map and calculate distance to the squad
	foreach ( hp in level.hardpoints )
	{
		local hpTeam = hp.GetTeam()
		local hpState = hp.GetHardpointState()
		local dist = Distance( squadOrigin, hp.GetOrigin() )

		// EMERGENCY CHECK: Is our owned point currently being contested or captured by the enemy?
		if ( hpTeam == team && ( hpState == CAPTURE_POINT_STATE_HALTED || hpState == CAPTURE_POINT_STATE_CAPPING ) )
		{
			if ( dist < closestEmergencyDist )
			{
				closestEmergencyDist = dist
				emergencyPoint = hp
			}
		}

		// Store the hardpoint and its distance in a table for sorting later
		local hpData = { point = hp, distance = dist }

		if ( hpTeam == team )
			ownedPoints.append( hpData )
		else if ( hpTeam == TEAM_UNASSIGNED )
			neutralPoints.append( hpData )
		else
			enemyPoints.append( hpData )
	}

	// ---------------------------------------------------------
	// DEFENDER LOGIC
	// ---------------------------------------------------------
	if ( role == "defend" )
	{
		// 1. Defend the closest emergency point immediately
		if ( emergencyPoint != null )
			return emergencyPoint
			
		// 2. Otherwise, garrison the closest owned point
		if ( ownedPoints.len() > 0 )
		{
			ownedPoints.sort( SortByDistance )
			return ownedPoints[0].point 
		}
	}

	// ---------------------------------------------------------
	// ATTACKER LOGIC
	// ---------------------------------------------------------
	// 1. Prioritize the closest Neutral points first for early leads
	if ( neutralPoints.len() > 0 )
	{
		neutralPoints.sort( SortByDistance )
		return neutralPoints[0].point
	}

	// 2. If no Neutral points, push the closest Enemy point
	if ( enemyPoints.len() > 0 )
	{
		enemyPoints.sort( SortByDistance )
		return enemyPoints[0].point
	}

	// ---------------------------------------------------------
	// FALLBACK LOGIC
	// ---------------------------------------------------------
	// If we own all 3 points, even attackers must fall back to defend the closest point
	if ( ownedPoints.len() > 0 )
	{
		ownedPoints.sort( SortByDistance )
		return ownedPoints[0].point
	}

	return level.hardpoints[0]
}

// Helper function to sort tables by the "distance" key
function SortByDistance( a, b ) 
{
	if ( a.distance > b.distance ) return 1
	if ( a.distance < b.distance ) return -1
	return 0
}

function AssaultTDM( guys, index )
{
	if ( !guys.len() )
		return

	//give everyone proper squad name
	local team 		= guys[ 0 ].GetTeam()

	local squadName = MakeSquadName( team, index )

	foreach( guy in guys )
		SetSquad( guy, squadName )

	//is our squad filled up yet?
	local squad = GetNPCArrayBySquad( squadName )

	if ( squad.len() > SQUADSIZE )
		return

	//ok we got everyone - lets assault some shit
	thread SquadAssaultFrontline( squad, index )
}

//=========================================================
// CTF AI SUPPORT
//=========================================================
// Dispatches squads with dynamic flag-state-driven objectives:
//   - Enemy flag at home      -> push toward enemy flag base (capture pressure)
//   - Enemy flag held by ally -> fall back to defend own flag base (escort intent)
//   - Enemy flag dropped      -> move to recover it
//   - Own flag held by enemy  -> hunt the carrier
//   - Own flag dropped        -> move to return point
// NPCs that physically touch the enemy flag WILL pick it up if the engine allows
// it (forceDisableFlagTouch is per-entity, which suggests it's gated this way).
// If NPCs cannot carry, grunts still provide defensive pressure and distraction.
// (Constants CTF_FLAGRUN_GOAL_RADIUS / CTF_FLAGRUN_REEVAL_PERIOD / CTF_DEBUG are
//  declared at the top of this file.)


function AssaultCTF( guys, index )
{
	if ( !guys.len() )
		return

	// give everyone proper squad name
	local team 		= guys[ 0 ].GetTeam()
	local squadName = MakeSquadName( team, index )

	foreach( guy in guys )
	{
		if ( IsValid( guy ) )
			SetSquad( guy, squadName )
	}

	// is our squad filled up yet?
	local squad = GetNPCArrayBySquad( squadName )

	if ( squad.len() > SQUADSIZE )
		return

	// 2:1 attacker bias -- squad indices 0 and 1 push the enemy flag, index 2 holds own base.
	// With level.aiSquadCount = 3, this gives 2 attacking squads vs 1 defending squad per team.
	local role = ( index < 2 ) ? "attack" : "defend"

	thread SquadFlagRunThink( squadName, team, role )
}


// Locates the flag base origin for the given team.
// Probes the known flag-storage surfaces in order: flagSpawnPoints array, then
// the flagSpawnPoint/flagReturnPoint legacy single-team vars, then a model scan.
// Successful lookups are cached on level.ctfFlagOriginCache since flag bases don't move.
// Returns a Vector or null.
function GetCTFFlagOriginForTeam( team )
{
	if ( !( "ctfFlagOriginCache" in level ) )
		level.ctfFlagOriginCache <- {}

	if ( team in level.ctfFlagOriginCache )
		return level.ctfFlagOriginCache[ team ]

	local found = null
	local foundVia = "none"	// for diagnostics

	// Preferred: flagSpawnPoints is a list with per-ent team info
	if ( "flagSpawnPoints" in level )
	{
		foreach ( sp in level.flagSpawnPoints )
		{
			if ( !IsValid( sp ) )
				continue
			if ( sp.GetTeam() == team )
			{
				found = sp.GetOrigin()
				foundVia = "flagSpawnPoints[]"
				break
			}
		}
	}

	// Legacy single-team globals. These are ambiguous about team ownership --
	// flagSpawnPoint tends to be "home" and flagReturnPoint the other.
	// Best-effort: if the var exists and its team matches, use it.
	if ( found == null && "flagSpawnPoint" in level && IsValid( level.flagSpawnPoint ) )
	{
		if ( level.flagSpawnPoint.GetTeam() == team )
		{
			found = level.flagSpawnPoint.GetOrigin()
			foundVia = "flagSpawnPoint"
		}
	}

	if ( found == null && "flagReturnPoint" in level && IsValid( level.flagReturnPoint ) )
	{
		if ( level.flagReturnPoint.GetTeam() == team )
		{
			found = level.flagReturnPoint.GetOrigin()
			foundVia = "flagReturnPoint"
		}
	}

	// Fallback: scan the world for the flag base model and match by team.
	// CTF_FLAG_BASE_MODEL is precached in _base_gametype.nut and is the visible pedestal.
	if ( found == null )
	{
		local candidates = GetEntArrayByClass_Expensive( "prop_dynamic" )
		foreach ( ent in candidates )
		{
			if ( !IsValid( ent ) )
				continue
			if ( ent.GetModelName() != CTF_FLAG_BASE_MODEL )
				continue
			if ( ent.GetTeam() == team )
			{
				found = ent.GetOrigin()
				foundVia = "model_scan"
				break
			}
		}
	}

	// Only cache successful lookups; a null result may just mean we ran too early.
	if ( found != null )
	{
		level.ctfFlagOriginCache[ team ] <- found
		if ( CTF_DEBUG )
			printt( "[CTF_AI] Flag base for team", team, "resolved via", foundVia, "at", found )
	}
	else if ( CTF_DEBUG )
	{
		printt( "[CTF_AI] WARNING: No flag base found for team", team, "-- squad will not have attack objective" )
	}

	return found
}


// Locates the nearest living enemy flag carrier (player or NPC) for the given team.
// "Enemy carrier" from my perspective means someone on the enemy team carrying MY flag.
// Returns an entity or null.
function GetEnemyFlagCarrierForTeam( team )
{
	local enemyTeam = ( team == TEAM_IMC ) ? TEAM_MILITIA : TEAM_IMC

	// Check players first -- by far the most common case
	foreach ( player in GetPlayerArrayOfTeam( enemyTeam ) )
	{
		if ( !IsValid( player ) || !IsAlive( player ) )
			continue
		// PlayerHasEnemyFlag from the carrier's perspective: does this enemy have OUR flag?
		// From our perspective they have "our" flag; from theirs it's the "enemy" flag. Same check.
		if ( PlayerHasEnemyFlag( player ) )
			return player
	}

	// Also check NPCs on the enemy team in case engine allows NPC carry
	local npcs = GetNPCArray()
	foreach ( npc in npcs )
	{
		if ( !IsValid( npc ) || !IsAlive( npc ) )
			continue
		if ( npc.GetTeam() != enemyTeam )
			continue
		if ( PlayerHasEnemyFlag( npc ) )
		{
			if ( CTF_DEBUG )
				printt( "[CTF_AI] ENEMY NPC IS CARRYING OUR FLAG:", npc, "class:", npc.GetClassname(), "team:", npc.GetTeam(), "origin:", npc.GetOrigin() )
			return npc
		}
	}

	return null
}

// Determines what objective the squad should pursue based on current flag state.
// Returns a table { origin = Vector, radius = int } or null if no sensible objective exists.
// `team` is the squad's own team. `role` is "attack" or "defend".
function GetCTFObjectiveForTeam( team, role )
{
	local enemyTeam  = ( team == TEAM_IMC ) ? TEAM_MILITIA : TEAM_IMC
	local ownBase    = GetCTFFlagOriginForTeam( team )
	local enemyBase  = GetCTFFlagOriginForTeam( enemyTeam )

	// If own flag is being carried by an enemy, hunt the carrier regardless of role.
	local theirCarrier = GetEnemyFlagCarrierForTeam( team )
	if ( IsValid( theirCarrier ) )
		return { origin = theirCarrier.GetOrigin(), radius = CTF_FLAGRUN_GOAL_RADIUS }

	// Defenders bias toward own base unless own flag is actually away.
	if ( role == "defend" )
	{
		if ( ownBase != null )
			return { origin = ownBase, radius = CTF_FLAGRUN_GOAL_RADIUS }
		// fall through if we can't find our base
	}

	// Attackers (and defenders with no home to defend) push the enemy flag.
	// If a friendly is carrying the enemy flag, escort them directly with a tight radius.
	local ourCarrier = null
	foreach ( player in GetPlayerArrayOfTeam( team ) )
	{
		if ( IsValid( player ) && IsAlive( player ) && PlayerHasEnemyFlag( player ) )
		{
			ourCarrier = player
			break
		}
	}
	if ( !IsValid( ourCarrier ) )
	{
		local npcs = GetNPCArray()
		foreach ( npc in npcs )
		{
			if ( !IsValid( npc ) || !IsAlive( npc ) )
				continue
			if ( npc.GetTeam() != team )
				continue
			if ( PlayerHasEnemyFlag( npc ) )
			{
				if ( CTF_DEBUG )
					printt( "[CTF_AI] FRIENDLY NPC IS CARRYING ENEMY FLAG:", npc, "class:", npc.GetClassname(), "team:", npc.GetTeam(), "origin:", npc.GetOrigin() )
				ourCarrier = npc
				break
			}
		}
	}

	if ( IsValid( ourCarrier ) )
	{
		// Escort mode -- stick close to the carrier with a tight radius so grunts
		// actually form a protective bubble rather than drifting to the home base.
		return { origin = ourCarrier.GetOrigin(), radius = CTF_FLAGRUN_ESCORT_RADIUS }
	}

	// Default: push the enemy flag base
	if ( enemyBase != null )
		return { origin = enemyBase, radius = CTF_FLAGRUN_GOAL_RADIUS }

	// Last resort: if we literally can't find any flag base, hold position
	return null
}


// Squad think loop for CTF. Re-evaluates objective every CTF_FLAGRUN_REEVAL_PERIOD
// seconds or whenever level.ent signals "FlagUpdate", whichever comes first.
// Uses a per-squad signal name so starting a fresh think for one squad doesn't
// cancel sibling squads on the same team (we have up to level.aiSquadCount per team).
function SquadFlagRunThink( squadName, team, role )
{
	local signalString = "SquadFlagRunThink_" + squadName

	level.ent.Signal( signalString )
	level.ent.EndSignal( signalString )

	if ( !GetNPCSquadSize( squadName ) )
		return

	local lastGoal = null

	while ( true )
	{
		local squad = GetNPCArrayBySquad( squadName )
		ArrayRemoveDead( squad )

		if ( !squad.len() )
			return

		local goal = GetCTFObjectiveForTeam( team, role )

		if ( goal != null )
		{
			// only reissue orders if the goal meaningfully moved, to avoid spamming assault ents.
			// use the tightest common radius (escort radius) as the "moved enough" threshold so
			// escort squads actually re-home on the carrier every tick rather than lagging behind.
			if ( lastGoal == null || Distance( goal.origin, lastGoal ) > CTF_FLAGRUN_ESCORT_RADIUS )
			{
				if ( CTF_DEBUG )
					printt( "[CTF_AI] squad", squadName, "role=" + role, "new goal:", goal.origin, "radius:", goal.radius )
				SquadAssaultOrigin( squad, goal.origin, goal.radius )
				lastGoal = goal.origin
			}
		}

		// Wait either for the periodic re-eval or a flag state change, whichever comes first.
		// waitthread on a helper so we get race-free select semantics.
		waitthread CTFFlagRunWaitTick()
	}
}


// Helper: wait for either FlagUpdate signal or the reeval period, whichever is first.
function CTFFlagRunWaitTick()
{
	level.ent.EndSignal( "FlagUpdate" )
	wait CTF_FLAGRUN_REEVAL_PERIOD
}


//=========================================================
// CTF FAKE-CAPTURE (grunt-delivered score)
//=========================================================
// Since NPCs cannot physically pick up flags, we simulate a "capture" when a friendly
// grunt reaches the enemy flag base. This awards a team score point but does not trigger
// the visual flag attachment or the full capture sequence (announcer, VFX, flag reset).
//
// Safety rails:
//   - Only fires when the enemy flag is at home (no player/NPC carrying it)
//   - Hard cap of CTF_FAKECAP_MAX_PER_TEAM captures per team per match
//   - Per-team cooldown of CTF_FAKECAP_TEAM_COOLDOWN seconds between fires
//   - Never fires if awarding the point would end the match (preserves "let a player
//     finish the match" intent; grunt help is assistance, not victory delivery)

function CTFFakeCaptureWatchdog()
{
	printt( "[CTF_AI] WATCHDOG: entered function body" )

	// Per-team bookkeeping. Initialize first so downstream helpers can rely on these being present.
	level.ctfFakeCapCount       <- { [TEAM_IMC] = 0, [TEAM_MILITIA] = 0 }
	printt( "[CTF_AI] WATCHDOG: ctfFakeCapCount initialized" )

	level.ctfFakeCapLastTime    <- { [TEAM_IMC] = 0.0, [TEAM_MILITIA] = 0.0 }
	printt( "[CTF_AI] WATCHDOG: ctfFakeCapLastTime initialized" )

	level.ctfFakeCapLastDiagTime <- { [TEAM_IMC] = 0.0, [TEAM_MILITIA] = 0.0 }	// used by ShouldPrintFakeCapGateDiag( team ) for throttled logging

	printt( "[CTF_AI] fake-capture watchdog started (max per team:", CTF_FAKECAP_MAX_PER_TEAM, "cooldown:", CTF_FAKECAP_TEAM_COOLDOWN, "s)" )

	local loopCount = 0
	local prevGameState = GetGameState()

	while ( true )
	{
		wait CTF_FAKECAP_CHECK_PERIOD

		loopCount = loopCount + 1
		// every 20 iterations, print a heartbeat so we know the thread is alive (~10s wallclock at 0.5s polls)
		if ( loopCount % 20 == 0 )
			printt( "[CTF_AI] WATCHDOG: heartbeat loop=", loopCount, "state=", GetGameState() )

		local curGameState = GetGameState()

		// Round-transition reset. CTF is switch-sides round-based: gamestate goes
		// Playing -> SwitchingSides -> Playing for round 2. When we re-enter Playing from any
		// non-Playing state, wipe the per-team cap counters and cooldowns so round 2 starts
		// fresh -- otherwise the previous round's cooldown-free state lets grunts cap rapidly
		// in the opening seconds of the new round.
		if ( curGameState == eGameState.Playing && prevGameState != eGameState.Playing )
		{
			printt( "[CTF_AI] round transition detected (", prevGameState, "->", curGameState, ") - resetting fake-cap bookkeeping" )
			level.ctfFakeCapCount[ TEAM_IMC ]     = 0
			level.ctfFakeCapCount[ TEAM_MILITIA ] = 0
			level.ctfFakeCapLastTime[ TEAM_IMC ]     = Time()
			level.ctfFakeCapLastTime[ TEAM_MILITIA ] = Time()
			// Setting LastTime to now means the 30s cooldown is effectively re-armed at round start.
			// That gives players a grace period to engage before grunts can start capping.
		}

		prevGameState = curGameState

		if ( curGameState != eGameState.Playing )
			continue

		CTFFakeCaptureCheckTeam( TEAM_IMC )
		CTFFakeCaptureCheckTeam( TEAM_MILITIA )
	}
}

// Throttle for gate-diagnostic prints. Returns true once every ~5 seconds PER TEAM so we can see
// per-team status (closest NPC distance, etc) without spamming the console every tick.
function ShouldPrintFakeCapGateDiag( team )
{
	if ( Time() - level.ctfFakeCapLastDiagTime[ team ] >= 5.0 )
	{
		level.ctfFakeCapLastDiagTime[ team ] = Time()
		return true
	}
	return false
}

function CTFFakeCaptureCheckTeam( team )
{
	// Hard cap check -- short-circuit if this team has already used all its fake captures
	if ( level.ctfFakeCapCount[ team ] >= CTF_FAKECAP_MAX_PER_TEAM )
	{
		if ( CTF_DEBUG && ShouldPrintFakeCapGateDiag( team ) )
			printt( "[CTF_AI] GATE team", team, "CAP REACHED (", level.ctfFakeCapCount[ team ], "/", CTF_FAKECAP_MAX_PER_TEAM, ")" )
		return
	}

	// Cooldown check
	local timeSinceLast = Time() - level.ctfFakeCapLastTime[ team ]
	if ( timeSinceLast < CTF_FAKECAP_TEAM_COOLDOWN )
	{
		if ( CTF_DEBUG && ShouldPrintFakeCapGateDiag( team ) )
			printt( "[CTF_AI] GATE team", team, "COOLDOWN (", timeSinceLast, "s /", CTF_FAKECAP_TEAM_COOLDOWN, "s)" )
		return
	}

	local enemyTeam = ( team == TEAM_IMC ) ? TEAM_MILITIA : TEAM_IMC
	local enemyBase = GetCTFFlagOriginForTeam( enemyTeam )

	if ( enemyBase == null )
	{
		if ( CTF_DEBUG && ShouldPrintFakeCapGateDiag( team ) )
			printt( "[CTF_AI] GATE team", team, "NO ENEMY BASE RESOLVED" )
		return
	}

	// Require that the enemy flag is actually at home (not being carried).
	foreach ( player in GetPlayerArray() )
	{
		if ( IsValid( player ) && IsAlive( player ) && PlayerHasEnemyFlag( player ) )
		{
			if ( CTF_DEBUG && ShouldPrintFakeCapGateDiag( team ) )
				printt( "[CTF_AI] GATE team", team, "PLAYER CARRYING FLAG:", player )
			return
		}
	}
	local allNpcs = GetNPCArray()
	foreach ( npc in allNpcs )
	{
		if ( IsValid( npc ) && IsAlive( npc ) && PlayerHasEnemyFlag( npc ) )
		{
			if ( CTF_DEBUG && ShouldPrintFakeCapGateDiag( team ) )
				printt( "[CTF_AI] GATE team", team, "NPC CARRYING FLAG:", npc )
			return
		}
	}

	// NOTE: match-end guard removed by user request 2026-04-17 -- grunt captures are now allowed to
	// deliver the winning point. Previously we suppressed fake caps when currentScore+1 >= scoreLimit
	// so players would always get the final kill. Per user feedback the 2-per-team cap was already
	// limiting grunt contribution enough; letting them close out the match feels fine.

	// Position check: find the CLOSEST friendly grunt to the enemy base. Report distance
	// for diagnostics so we can tell if grunts are ever getting close enough.
	local triggeringGrunt = null
	local closestNpc = null
	local closestDist = 999999.0
	local candidateCount = 0

	foreach ( npc in allNpcs )
	{
		if ( !IsValid( npc ) || !IsAlive( npc ) )
			continue
		if ( npc.GetTeam() != team )
			continue
		if ( !npc.IsNPC() )
			continue
		candidateCount = candidateCount + 1

		local dist = Distance( npc.GetOrigin(), enemyBase )
		if ( dist < closestDist )
		{
			closestDist = dist
			closestNpc  = npc
		}
		if ( dist <= CTF_FAKECAP_TRIGGER_DIST )
		{
			triggeringGrunt = npc
			break
		}
	}

	// Telemetry print so we can see what the closest friendly NPC to the enemy base is
	if ( CTF_DEBUG && ShouldPrintFakeCapGateDiag( team ) )
	{
		if ( closestNpc != null )
			printt( "[CTF_AI] GATE team", team, "closest-of-", candidateCount, "NPC at dist", closestDist, "to enemyBase (trigger threshold:", CTF_FAKECAP_TRIGGER_DIST, ") --", closestNpc )
		else
			printt( "[CTF_AI] GATE team", team, "NO LIVING FRIENDLY NPCs at all (candidateCount=", candidateCount, ")" )
	}

	if ( !IsValid( triggeringGrunt ) )
		return

	// All gates passed -- award the capture
	CTFAwardFakeCapture( team, triggeringGrunt )
}

function CTFAwardFakeCapture( team, grunt )
{
	GameScore.AddTeamScore( team, 1 )

	level.ctfFakeCapCount[ team ]    = level.ctfFakeCapCount[ team ] + 1
	level.ctfFakeCapLastTime[ team ] = Time()

	// Notify players with a HUD message. SendHudMessage params:
	//   (player, text, x, y, r, g, b, a, fadeIn, holdTime, fadeOut)
	// x=-1 means horizontally centered, y is vertical anchor (0 top, 1 bottom).
	// Friendly = bright green, enemy = red, both prominently placed.
	
	/*
	foreach ( player in GetPlayerArray() )
	{
		if ( !IsValid( player ) )
			continue

		local playerTeam = player.GetTeam()
		local msg
		local r = 255
		local g = 255
		local b = 255

		if ( IsValid( grunt ) && grunt.IsNPC() && playerTeam == team )
		{
			msg = "Friendly squad captured the enemy flag!"
			r = 80; g = 255; b = 80		// green
		}
		else if ( IsValid( grunt ) && grunt.IsNPC() && playerTeam != team )
		{
			msg = "Enemy squad captured our flag!"
			r = 255; g = 80; b = 80		// red
		}

		SendHudMessage( player, msg, -1, 0.3, r, g, b, 255, 0.2, 4.0, 0.5 )
	}
	*/

	// Play the proper "flag captured" announcer lines. The dialogue system registers
	// friendly_captured_flag / enemy_captured_flag for each team -- playing one per team
	// makes each player hear the appropriate side (their team's friendly line, or the
	// enemy's enemy line). This fires the same triumphant "we captured the enemy flag!"
	// VO that plays on a real player capture.
	foreach ( listener in GetPlayerArray() )
	{
		if ( !IsValid( listener ) )
			continue

		local alias = ( listener.GetTeam() == team ) ? "friendly_captured_flag" : "enemy_captured_flag"
		PlayConversationToPlayer( alias, listener )
	}

	if ( CTF_DEBUG )
	{
		local newScore = GameRules.GetTeamScore( team )
		printt( "[CTF_AI] *** FAKE CAPTURE *** team", team, "grunt", grunt, "at", grunt.GetOrigin(),
				"-- team score now", newScore, "(grunt-caps used:", level.ctfFakeCapCount[ team ], "/", CTF_FAKECAP_MAX_PER_TEAM, ")" )
	}
}


// Puedes poner esto al final de tu archivo o dentro de una función de debug

function DebugSpawnPilotInfantry( team )
{
    local pilotmodels = file.pilotmodels
    if ( team == TEAM_MILITIA )
        pilotmodels = file.militiapilotmodels
    else if ( team == TEAM_IMC )
        pilotmodels = file.imcpilotmodels

    // Usa el primer spawnpoint de droppod como referencia
    local spawnPoints = SpawnPoints_GetDropPodStart( team )
    if ( spawnPoints.len() == 0 )
    {
        printt("No spawnpoints found for team", team)
        return
    }
    local baseOrigin = spawnPoints[0].GetOrigin()
    local baseAngles = spawnPoints[0].GetAngles()

    for (local i = 0; i < 4; i++)
    {
        local offset = Vector( i * 32, 0, 0 ) // separa un poco a cada piloto
        local pilot = CreateEntity( "npc_soldier" )
        DispatchSpawn( pilot )
        pilot.SetOrigin( baseOrigin + offset )
        pilot.SetAngles( baseAngles )
        pilot.SetTeam( team )
        pilot.SetModel( Random( pilotmodels ) )
        SetNPCAsPilot( pilot, true )
        GiveMinionWeapon( pilot, "mp_weapon_rspn101" )
        pilot.SetMaxHealth( 200 )
        pilot.SetHealth( 200 )
        printt("Spawned pilot at", pilot.GetOrigin())
    }
}
Globalize( DebugSpawnPilotInfantry )

//////////////////////////////////////
const NUKE_TITAN_PLAYER_DETECT_RANGE 	= 500
const NUKE_TITAN_RANGE_CHECK_SLEEP_SECS = 1.0
const NUKE_TITAN_DAMAGES_OTHER_NPCS = false

function AutoTitan_NuclearPayload_DamageCallback( titan, damageInfo )
{
	if ( !IsAlive( titan ) )
		return

	local titanOwner = titan.GetBossPlayer()
	if ( IsValid( titanOwner ) )
	{
		Assert( titanOwner.IsPlayer() )
		Assert( GetPlayerTitanInMap( titanOwner ) == titan )
		return
	}

	local nuclearPayload = NPC_GetNuclearPayload( titan )
	if ( !nuclearPayload )
		return

	if ( !titan.GetDoomedState() )
		return

	if ( titan.GetTitanSoul().IsEjecting() )
		return

	// - if a player titan is nearby, try to nuke right next to him
	if ( !AutoTitan_IsPlayerTitanInRange( titan, NUKE_TITAN_PLAYER_DETECT_RANGE ) )
	{
		// Otherwise try to nuke at a semirandom doomed state health fraction. (Like a player, more random.)
		if ( !( "doomedStateNukeTriggerHealth" in titan.s ) )
		{
			local lowEnd = floor( ( titan.GetMaxHealth() * 0.95 ) + 0.5 )
			local highEnd = floor( ( titan.GetMaxHealth() * 0.99 ) + 0.5 )

			titan.s.doomedStateNukeTriggerHealth <- RandomInt( lowEnd, highEnd )
		}

		if ( titan.GetHealth() > titan.s.doomedStateNukeTriggerHealth )
		{
			//printt( "titan health:", titan.GetHealth(), "health to nuke:", titan.s.doomedStateNukeTriggerHealth )
			return
		}

		printt( "NUKE TITAN DOOMED TRIGGER HEALTH REACHED, NUKING! Health:", titan.s.doomedStateNukeTriggerHealth )
	}
	else
	{
		printt( "PLAYER TITAN IN RANGE, NUKING!" )
	}

	thread TitanEjectPlayer( titan )
}

function AutoTitan_IsPlayerTitanInRange( autoTitan, maxDist )
{
	// Distance checks are expensive, don't do them as often as a damage callback could happen (every frame)
	if ( !AutoTitan_CanDoRangeCheck( autoTitan ) )
		return false

	local testOrg = autoTitan.GetOrigin()
	foreach ( player in GetPlayerArray() )
	{
		local playerTitan = player
		if ( !player.IsTitan() )
		{
			playerTitan = GetPlayerTitanInMap( player )

			if ( !playerTitan )
				continue
		}

		if ( Distance( testOrg, playerTitan.GetOrigin() ) <= maxDist )
			return true
	}

	return false
}

function AutoTitan_CanDoRangeCheck( autoTitan )
{
	if ( !( "nextPlayerTitanRangeCheckTime" in autoTitan.s ) )
		autoTitan.s.nextPlayerTitanRangeCheckTime <- -1

	if ( Time() < autoTitan.s.nextPlayerTitanRangeCheckTime )
	{
		return false
	}
	else
	{
		autoTitan.s.nextPlayerTitanRangeCheckTime = Time() + NUKE_TITAN_RANGE_CHECK_SLEEP_SECS
		return true
	}
}


//////////////////////////
// Ripped this stuff down here from Auto Titan Brawl to make the Titans more aggressive
// ...Look man, don't ask questions. It just works


function TitanBrawlAuto_HuntThink( titan, entry )
{
    titan.EndSignal( "OnDeath" )
    titan.EndSignal( "OnDestroy" )

    local lastValidTargetTime = Time()
    local lastPosition = titan.GetOrigin()
    local lastPositionCheckTime = Time()
    local stuckThreshold = 2.0  // If titan hasn't moved in 2 seconds, it's stuck
    local minMovementDistance = 100.0  // Minimum distance to consider "moved"

    while ( true )
    {
        // Check if titan is stuck (hasn't moved significantly)
        local currentTime = Time()
        local currentPosition = titan.GetOrigin()
        local timeSinceLastCheck = currentTime - lastPositionCheckTime

        if ( timeSinceLastCheck >= stuckThreshold )
        {
            local distanceMoved = Distance( currentPosition, lastPosition )

            if ( distanceMoved < minMovementDistance )
            {
                // Titan is stuck! Force it to find a new location
                printt("[AutoTitan]", entry.name, "is stuck, forcing new target")
                TitanBrawlAuto_SendToRandomLocation( titan, entry )
                lastValidTargetTime = currentTime
            }

            lastPosition = currentPosition
            lastPositionCheckTime = currentTime
        }

        local target = TitanBrawlAuto_SelectTarget( titan, entry )
        if ( IsValid( target ) )
        {
			printt("TARGET:" + target)
            titan.SetEnemy( target )
            SendAIToAssaultPoint( titan, target.GetOrigin(), null, 256 )
            lastValidTargetTime = currentTime
        }
        else
        {
            // No valid target - make titan roam to prevent standing still
            local timeSinceLastTarget = currentTime - lastValidTargetTime
            if ( timeSinceLastTarget >= 1.0 )
            {
                TitanBrawlAuto_SendToRandomLocation( titan, entry )
                lastValidTargetTime = currentTime
            }
        }
        wait RandomFloat( 1.5, 3.0 )
    }
}

function TitanBrawlAuto_SendToRandomLocation( titan, entry )
{
    // Try to find a random assault point or spawn point to patrol to
    local enemyTeam = GetOtherTeam( entry.team )
    local assaultPoints = GetEntArrayByClass_Expensive( "info_frontline" )

    if ( assaultPoints.len() > 0 )
    {
        local randomPoint = assaultPoints[ RandomInt( assaultPoints.len() ) ]
        SendAIToAssaultPoint( titan, randomPoint.GetOrigin(), null, 512 )
        return
    }

    // Fallback: move toward enemy spawn
    local enemySpawns = SpawnPoints_GetTitanStart( enemyTeam )
    if ( enemySpawns.len() > 0 )
    {
        local randomSpawn = enemySpawns[ RandomInt( enemySpawns.len() ) ]
        SendAIToAssaultPoint( titan, randomSpawn.GetOrigin(), null, 512 )
        return
    }

    // Last resort: move in a random direction
    local currentPos = titan.GetOrigin()
    local randomOffset = Vector( RandomFloat( -1000, 1000 ), RandomFloat( -1000, 1000 ), 0 )
    local newPos = currentPos + randomOffset
    SendAIToAssaultPoint( titan, newPos, null, 256 )
}

function TitanBrawlAuto_SelectTarget( titan, entry )
{
    local enemyTeam = GetOtherTeam( entry.team )
    local origin = titan.GetOrigin()
    
    // Priority 1: Players (only spotted ones) and ALL Titans
    local highPriority = []
    
    // Add spotted players only
    local enemyPlayers = GetPlayerArrayOfTeam( enemyTeam )
    foreach ( player in enemyPlayers )
    {
        if ( player in entry.spottedPlayers )
            highPriority.append( player )
    }
    
    // Add ALL enemy titans (always valid targets)
    highPriority.extend( GetNPCArrayEx( "npc_titan", enemyTeam, origin, -1 ) )
    
	foreach ( otherEntry in level.autoTitanData[ enemyTeam ] )
	{
		if ( !(otherEntry.titan in highPriority) )
			highPriority.append(otherEntry.titan)
	}
    
    // Check high priority targets first
    local best = TitanBrawlAuto_FindClosestValid( highPriority, origin )
    if ( best != null )
        return best
    
    // Priority 2: Low priority NPCs (soldiers/spectres)
    local lowPriority = []
    lowPriority.extend( GetNPCArrayEx( "npc_soldier", enemyTeam, origin, -1 ) )
    lowPriority.extend( GetNPCArrayEx( "npc_spectre", enemyTeam, origin, -1 ) )
    
    return TitanBrawlAuto_FindClosestValid( lowPriority, origin )
}

function TitanBrawlAuto_FindClosestValid( candidates, origin )
{
    local closest = null
    local closestDist = 999999

    foreach ( candidate in candidates )
    {
        if ( !IsValid(candidate) )
            continue

        if ( !IsAlive(candidate) )
            continue

        local d = Distance(origin, candidate.GetOrigin())

        if ( d < closestDist )
        {
            closest = candidate
            closestDist = d
        }
    }

    return closest
}


////////////////////////////////////////////////////////////////
//////////////// CLOAK DRONES /////////////////////
////////////////////////////////////////////////////////////////

const CLOAKED_DRONE_SPEED		= 1800
const CLOAKED_DRONE_ACC		= 1.75
const CLOAKED_DRONE_YAWRATE	= 150
const CLOAKED_DRONE_LOOPING_SFX = "Coop_CloakDrone_Beam"
const CLOAKED_DRONE_WARP_IN_SFX = "Coop_DroneTeleport_In"
const CLOAKED_DRONE_WARP_OUT_SFX = "Coop_DroneTeleport_Out"
const CLOAKED_DRONE_CLOAK_START_SFX = "CloakDrone_Cloak_On"
const CLOAKED_DRONE_CLOAK_LOOP_SFX = "CloakDrone_Cloak_Sustain_Loop"
const CLOAKED_DRONE_HOVER_LOOP_SFX = "AngelCity_Scr_DroneSearchHover"

const MINIMAP_CLOAKED_DRONE_SCALE 		= 0.070


function SpawnCloakDrone( team, origin, angles )
{
	local mover = CreateEntity( "script_mover" )
	local droneCount = GetNPCCloakedDrones().len()

	// add some minor randomness to the spawn location as well as an offset based on number of drones in the world.
	origin += Vector( RandomInt( -64, 64 ), RandomInt( -64, 64 ), 300 + ( droneCount * 128 ) )

	mover.kv.solid = 6
	mover.kv.model = CLOAKED_DRONE_MODEL
	mover.kv.SpawnAsPhysicsMover = 1
	mover.SetOrigin( origin )
	mover.SetAngles( angles )
	DispatchSpawn( mover, true )
	mover.Hide()
	mover.NotSolid()

	mover.SetMaxSpeed( CLOAKED_DRONE_SPEED )
	mover.SetAccelScale( CLOAKED_DRONE_ACC )
	mover.SetYawRate( CLOAKED_DRONE_YAWRATE )

	local cloakedDrone = CreatePropDynamic( CLOAKED_DRONE_MODEL, mover.GetOrigin(), mover.GetAngles(), 2, 8000 )

	//these enable global damage callbacks for the cloakedDrone
	cloakedDrone.s.searchShipMover <- mover
	cloakedDrone.s.isSearchDrone <- true
	cloakedDrone.s.isCloakedDrone <- true
	cloakedDrone.s.fakeHealth <- 250
	cloakedDrone.s.fakeMaxHealth <- 250
	cloakedDrone.s.isHidden <- false
	cloakedDrone.s.fx <- null

	cloakedDrone.SetTeam( team )
	cloakedDrone.SetName( "Cloak Drone" )
	cloakedDrone.SetTitle( "#NPC_CLOAK_DRONE" )
	cloakedDrone.Fire( "SetAnimation", "idle" )
	cloakedDrone.SetHealth( cloakedDrone.s.fakeHealth )
	cloakedDrone.SetDamageNotifications( true )
	cloakedDrone.Solid()
	cloakedDrone.Show()
	cloakedDrone.SetParent( mover, "", true, 0 )
	cloakedDrone.MarkAsNonMovingAttachment()
	cloakedDrone.EnableAttackableByAI()
	// SetCustomSmartAmmoTarget( cloakedDrone, true )

	EmitSoundOnEntity( cloakedDrone, CLOAKED_DRONE_HOVER_LOOP_SFX )
	EmitSoundOnEntity( cloakedDrone, CLOAKED_DRONE_LOOPING_SFX )
	EmitSoundOnEntity( cloakedDrone, CLOAKED_DRONE_WARP_IN_SFX )

	cloakedDrone.s.fx = CreateDroneCloakBeam( cloakedDrone )


	SetObjectCanBeMeleed( cloakedDrone, true )
	SetVisibleEntitiesInConeQueriableEnabled( cloakedDrone, true )

	thread CloakedDronePathThink( cloakedDrone )
	thread CloakedDroneCloakThink( cloakedDrone )


	local players = GetPlayerArray()
    if ( players.len() == 0 )
        return false // If no player is in yet, don't spawn

	cloakedDrone.Minimap_SetDefaultMaterial( "vgui/hud/cloak_drone_minimap" )
	cloakedDrone.Minimap_SetEnemyMaterial( "vgui/hud/cloak_drone_minimap_orange" )
	cloakedDrone.Minimap_SetFriendlyMaterial( "vgui/hud/cloak_drone_minimap" )
    cloakedDrone.Minimap_SetAlignUpright( true )
    cloakedDrone.Minimap_AlwaysShow( TEAM_IMC, null )
    cloakedDrone.Minimap_AlwaysShow( TEAM_MILITIA, null )
	cloakedDrone.Minimap_SetObjectScale( MINIMAP_CLOAKED_DRONE_SCALE )
	cloakedDrone.Minimap_SetZOrder( 10 )

	ShowName( cloakedDrone )
	mover.SetMoveToPosition( mover.GetOrigin() )//without this the drone will just start dropping until it finds a valid path

	AddToGlobalCloakedDroneList( cloakedDrone )
	return cloakedDrone
}
Globalize( SpawnCloakDrone )

function AddToGlobalCloakedDroneList( cloakedDrone )
{
	AddToScriptManagedEntArray( level.cloakedDronesManagedEntArrayID, cloakedDrone )
}

function GetNPCCloakedDrones()
{
	return GetScriptManagedEntArray( level.cloakedDronesManagedEntArrayID )
}


function CloakedDroneWarpOutAndDestroy( cloakedDrone )
{
	cloakedDrone.EndSignal( "OnDestroy" )
	cloakedDrone.EndSignal( "OnDeath" )
	cloakedDrone.SetInvulnerable()

	CloakedDroneWarpOut( cloakedDrone, cloakedDrone.GetOrigin() )
	local mover = cloakedDrone.GetParent()

	if ( IsValid( mover ) )
		mover.Destroy()	// this destroys the cloackDrone propDynamic as well.
}


//HACK - this should probably move into code
function CloakedDroneCloakThink( cloakedDrone )
{
	cloakedDrone.EndSignal( "OnDestroy" )
	cloakedDrone.EndSignal( "OnDeath" )
	cloakedDrone.EndSignal( "DroneCrashing" )
	cloakedDrone.EndSignal( "DroneCleanup" )

	wait 2	// wait a few seconds since it would start cloaking before picking an npc to follow
			// some npcs might not be picked since they where already cloaked by accident.

	local offset = Vector( 0,0,-350 )
	local radius = 400
	local droneTeam = cloakedDrone.GetTeam()

	cloakedDrone.s.cloakList <- {}

	OnThreadEnd(
		function() : ( cloakedDrone )
		{
			local cloakList = clone cloakedDrone.s.cloakList
			foreach ( guy, value in cloakList )
			{
				if ( !IsAlive( guy ) )
					continue

				CloakedDroneDeCloaksGuy( cloakedDrone, guy )
			}
		}
	)

	while( 1 )
	{
		local origin = cloakedDrone.GetOrigin() + offset
		local ai = GetNPCArrayEx( "any", cloakedDrone.GetTeam(), origin, radius )
		local index = 0

		local waitTime = 1.5
		local startTime = Time()

		local cloakList = cloakedDrone.s.cloakList
		local decloakList = clone cloakList

		foreach( guy in ai )
		{
			//only do 5 distanceSqr / cansee checks per frame
			if ( index++ > 5 )
			{
				wait 0.1
				index = 0
				origin = cloakedDrone.GetOrigin() + offset
			}

			if ( !IsAlive( guy ) )
				continue

			if ( guy.GetTeam() != droneTeam )
				continue

			if ( !( guy.IsTitan() || guy.IsSpectre() || guy.IsSoldier() ) )
				continue

			if ( IsSniperSpectre( guy ) )
				continue

			if ( IsTitanBeingRodeod( guy ) )
				continue

			local canSee = guy.IsTitan() ? true : cloakedDrone.CanSee( guy ) // Titans are big, bypass LoS check
			if ( canSee && cloakedDrone.s.isHidden == false )
			{
				if ( guy in decloakList )
					delete decloakList[ guy ]	// if guy is in the decloakList remove him because he should be cloaked

				if ( guy in cloakList )
					continue

				if ( IsCloaked( guy ) )	// cloaked by another cloakedDrone
					continue

				cloakList[ guy ] <- true
				CloakedDroneCloaksGuy( cloakedDrone, guy )
			}
		}

		foreach( guy, value in decloakList )
		{
			// any guys still in the decloakList shouldn't be decloaked ... if alive.
			Assert( guy in cloakList )
			delete cloakList[ guy ]

			if ( IsAlive( guy ) )
				CloakedDroneDeCloaksGuy( cloakedDrone, guy )
		}

		local endTime = Time()
		local elapsedTime = endTime - startTime
		if ( elapsedTime < waitTime )
			wait waitTime - elapsedTime

		//DebugDrawSphere( origin, radius, 50, 100, 255, 1.5 )
	}
}


function CloakedDroneCloaksGuy( cloakedDrone, guy )
{
	ApplyDroneCloak( cloakedDrone, guy )

	EmitSoundOnEntity( guy, CLOAKED_DRONE_CLOAK_START_SFX )
	EmitSoundOnEntity( guy, CLOAKED_DRONE_CLOAK_LOOP_SFX )

	guy.Minimap_Hide( TEAM_IMC, null )
	guy.Minimap_Hide( TEAM_MILITIA, null )
}


function CloakedDroneDeCloaksGuy( cloakedDrone, guy )
{
	guy.SetCloakDuration( 0, 0, 1.5 )
	StopSoundOnEntity( guy, CLOAKED_DRONE_CLOAK_LOOP_SFX )
	guy.Minimap_AlwaysShow( TEAM_IMC, null )
	guy.Minimap_AlwaysShow( TEAM_MILITIA, null )
}

//HACK -> this should probably move into code
const VALIDPATHFRAC = 0.99

function CloakedDronePathThink( cloakedDrone )
{
	local mover = cloakedDrone.GetParent()
	Assert( mover != null )

	mover.EndSignal( "OnDestroy" )
	cloakedDrone.EndSignal( "OnDestroy" )
	mover.EndSignal( "OnDeath" )
	cloakedDrone.EndSignal( "OnDeath" )
	mover.EndSignal( "DroneCrashing" )
	cloakedDrone.EndSignal( "DroneCrashing" )
	cloakedDrone.EndSignal( "DroneCleanup" )

	local goalNPC = null
	local previousNPC = null
	local spawnOrigin = cloakedDrone.GetOrigin()
	local lastOrigin = cloakedDrone.GetOrigin()
	local stuckDistSqr = 64*64
	local targetLostTime = Time()
	local claimedGuys = []

	while( 1 )
	{
		while( goalNPC == null )
		{
			wait 1.0
			local testArray = GetNPCArrayEx( "any", cloakedDrone.GetTeam(), Vector(0,0,0), -1 )

			// remove guys already being followed by an cloakedDrone
			// or in other ways not suitable
			local NPCs = []
			foreach ( guy in testArray )
			{
				if ( !IsAlive( guy ) )
					continue

				if ( !( guy.IsTitan() || guy.IsSpectre() || guy.IsSoldier() ) )
					continue

				if ( IsSniperSpectre( guy ) )
					continue

				if ( IsSuicideSpectre( guy ) )
					continue

				if ( guy == previousNPC )
					continue

				if ( guy.ContextAction_IsBusy() )
					continue

				if ( guy.GetParent() != null )
					continue

				if ( IsCloaked( guy ) )
					continue

				if ( IsSquadCenterClose( guy ) == false )
					continue

				if ( "cloakedDrone" in guy.s && IsAlive( guy.s.cloakedDrone ) )
					continue

				if ( guy.kv.squadname != "" && CloakedDroneIsSquadClaimed( guy.kv.squadname ) )
					continue

				if ( IsTitanBeingRodeod( guy ) )
					continue

				NPCs.append( guy )
			}

			if ( NPCs.len() == 0 )
			{
				previousNPC = null

				if ( Time() - targetLostTime > 10 )
				{
					// couldn't find anything to cloak for 10 seconds so we'll warp out until we find something
					if ( cloakedDrone.s.isHidden == false )
						CloakedDroneWarpOut( cloakedDrone, spawnOrigin )
				}
				continue
			}

			goalNPC = FindBestCloakTarget( NPCs, cloakedDrone.GetOrigin() )
			Assert( goalNPC )
		}

		// thread DrawSelectedEnt( cloakedDrone, goalNPC )
		if ( goalNPC.kv.squadname != "" )
			CloakedDroneClaimSquad( cloakedDrone, goalNPC.kv.squadname )

		waitthread CloakedDronePathFollowNPC( cloakedDrone, goalNPC )

		CloakedDroneReleaseSquad( cloakedDrone )

		previousNPC = goalNPC
		goalNPC = null
		targetLostTime = Time()

		local distSqr = DistanceSqr( lastOrigin, mover.GetOrigin() )
		if ( distSqr < stuckDistSqr )
			CloakedDroneWarpOut( cloakedDrone, spawnOrigin )

		lastOrigin = cloakedDrone.GetOrigin()
	}
}

function CloakedDroneClaimSquad( cloakedDrone, squadname )
{
	if ( GetNPCSquadSize( squadname ) )
		level.cloakedDroneClaimedSquadList[ cloakedDrone ] <- squadname
}

function CloakedDroneReleaseSquad( cloakedDrone )
{
	if ( cloakedDrone in level.cloakedDroneClaimedSquadList )
		delete level.cloakedDroneClaimedSquadList[ cloakedDrone ]
}

function CloakedDroneIsSquadClaimed( squadname )
{
	local cloneTable = clone level.cloakedDroneClaimedSquadList
	foreach( cloakedDrone, squad in cloneTable )
	{
		if ( !IsAlive( cloakedDrone ) )
			delete level.cloakedDroneClaimedSquadList[ cloakedDrone ]
		else if ( squad == squadname )
			return true
	}
	return false
}

function CloakedDronePathFollowNPC( cloakedDrone, goalNPC )
{
	local mover = cloakedDrone.GetParent()
	Assert( mover != null )

	mover.EndSignal( "OnDestroy" )
	cloakedDrone.EndSignal( "OnDestroy" )
	mover.EndSignal( "OnDeath" )
	cloakedDrone.EndSignal( "OnDeath" )
	mover.EndSignal( "DroneCrashing" )
	cloakedDrone.EndSignal( "DroneCrashing" )
	goalNPC.EndSignal( "OnDeath" )
	goalNPC.EndSignal( "OnDestroy" )

	if ( !( "cloakedDrone" in goalNPC.s ) )
		goalNPC.s.cloakedDrone <- null
	goalNPC.s.cloakedDrone = cloakedDrone

	OnThreadEnd(
		function() : ( goalNPC )
		{
			if ( IsAlive( goalNPC ) )
				goalNPC.s.cloakedDrone = null
		}
	)

	local droneTeam = cloakedDrone.GetTeam()

	local maxs = Vector( 64, 64, 53.5 )//bigger than model to compensate for large effect
	local mins = Vector( -64, -64, -64 )
	local mask = cloakedDrone.GetPhysicsSolidMask()

	local defaultHeight 			= 300
	local traceHeightsLow			= [ -75, -150 ]
	local traceHeightsHigh			= [ 150, 300, 800, 1500 ]

	local waitTime 	= 0.25

	local path = {}
	path.start 		<- null
	path.goal 		<- null
	path.goalValid 	<- false
	path.lastHeight <- defaultHeight

	while( goalNPC.GetTeam() == droneTeam )
	{
		if ( IsTitanBeingRodeod( goalNPC ) )
			return

		local startTime = Time()
		path.goalValid 	= false

		CloakedDroneFindPathDefault( path, defaultHeight, mins, maxs, mover, cloakedDrone, goalNPC, mask )

		//find a new path if necessary
		if ( !path.goalValid )
		{
			//lets check some heights and see if any are valid
			CloakedDroneFindPathHorizontal( path, traceHeightsLow, defaultHeight, mins, maxs, mover, cloakedDrone, goalNPC, mask )

			if ( !path.goalValid )
			{
				//OK so no way to directly go to those heights - lets see if we can move vertically down,
				CloakedDroneFindPathVertical( path, traceHeightsLow, defaultHeight, mins, maxs, mover, cloakedDrone, goalNPC, mask )

				if ( !path.goalValid )
				{
					//still no good...lets check up
					CloakedDroneFindPathHorizontal( path, traceHeightsHigh, defaultHeight, mins, maxs, mover, cloakedDrone, goalNPC, mask )

					if ( !path.goalValid )
					{
						//no direct shots up - lets try moving vertically up first
						CloakedDroneFindPathVertical( path, traceHeightsHigh, defaultHeight, mins, maxs, mover, cloakedDrone, goalNPC, mask )
					}
				}
			}
		}

		// if we can't find a valid path find a new goal
		if ( !path.goalValid )
			break

		if ( cloakedDrone.s.isHidden == true )
			CloakedDroneWarpIn( cloakedDrone, cloakedDrone.GetOrigin() )

		local vec 		= path.goal - path.start
		local angles 	= VectorToAngles( vec )
		mover.SetDesiredYaw( angles.y )
		mover.SetMoveToPosition( path.goal )

		//DebugDrawLine( path.start + Vector(0,0,1), path.goal + Vector(0,0,1), 0, 255, 0, true, 1.0 )

		local endTime = Time()
		local elapsedTime = endTime - startTime
		if ( elapsedTime < waitTime )
			wait waitTime - elapsedTime
	}
}

function IsTitanBeingRodeod( npc )
{
	if ( !npc.IsTitan() )
		return false

	local soul = npc.GetTitanSoul()
	if ( !IsValid( soul ) )
		return false

	local rider = soul.GetRiderEnt()
	if ( !IsAlive( rider ) )
		return false

	if ( !rider.IsPlayer() )
		return false

	return true
}

function CloakedDroneFindPathDefault( path, defaultHeight, mins, maxs, mover, cloakedDrone, goalNPC, mask )
{
	local offset 	= Vector( 0, 0, defaultHeight )
	path.start 		= mover.GetOrigin()
	path.goal 		= GetCloakTargetOrigin( goalNPC ) + offset

	//find out if we can get there using the default height
	local result = TraceHull( path.start, path.goal, mins, maxs, cloakedDrone, mask, TRACE_COLLISION_GROUP_NONE )
	//DebugDrawLine( path.start, path.goal, 50, 0, 0, true, 1.0 )
	if ( result.fraction >= VALIDPATHFRAC )
	{
		path.lastHeight = defaultHeight
		path.goalValid 	= true
	}

	return path.goalValid
}

function CloakedDroneFindPathHorizontal( path, traceHeights, defaultHeight, mins, maxs, mover, cloakedDrone, goalNPC, mask )
{
	wait 0.1

	local offset, result, testHeight

	//slight optimization... recheck if the last time was also not the default height
	if ( path.lastHeight != defaultHeight )
	{
		offset 			= Vector( 0, 0, defaultHeight + path.lastHeight )
		path.start 		= mover.GetOrigin()
		path.goal 		= GetCloakTargetOrigin( goalNPC ) + offset

		result = TraceHull( path.start, path.goal, mins, maxs, cloakedDrone, mask, TRACE_COLLISION_GROUP_NONE )
		//DebugDrawLine( path.start, path.goal, 0, 255, 0, true, 1.0 )
		if ( result.fraction >= VALIDPATHFRAC )
		{
			path.goalValid = true
			return path.goalValid
		}
	}

	for ( local i = 0; i < traceHeights.len(); i++ )
	{
		testHeight = traceHeights[ i ]
		if ( path.lastHeight == testHeight )
			continue

		wait 0.1

		offset 			= Vector( 0, 0, defaultHeight + testHeight )
		path.start 		= mover.GetOrigin()
		path.goal 		= GetCloakTargetOrigin( goalNPC ) + offset

		result = TraceHull( path.start, path.goal, mins, maxs, cloakedDrone, mask, TRACE_COLLISION_GROUP_NONE )
		if ( result.fraction < VALIDPATHFRAC )
		{
			//DebugDrawLine( path.start, path.goal, 200, 0, 0, true, 3.0 )
			continue
		}

		//DebugDrawLine( path.start, path.goal, 0, 255, 0, true, 3.0 )

		path.lastHeight = testHeight
		path.goalValid = true
		break
	}

	return path.goalValid
}

function CloakedDroneFindPathVertical( path, traceHeights, defaultHeight, mins, maxs, mover, cloakedDrone, goalNPC, mask )
{
	local offset, result, origin, testHeight

	for ( local i = 0; i < traceHeights.len(); i++ )
	{
		wait 0.1

		testHeight 		= traceHeights[ i ]
		origin 			= mover.GetOrigin()
		offset 			= Vector( 0, 0, defaultHeight + testHeight )
		path.start 		= Vector( origin.x, origin.y, defaultHeight + testHeight )
		path.goal 		= GetCloakTargetOrigin( goalNPC ) + offset

		result = TraceHull( path.start, path.goal, mins, maxs, cloakedDrone, mask, TRACE_COLLISION_GROUP_NONE )
		//DebugDrawLine( path.start, path.goal, 50, 50, 100, true, 1.0 )
		if ( result.fraction < VALIDPATHFRAC )
			continue

		//ok so it's valid - lets see if we can move to it from where we are
		wait 0.1

		path.goal 	= Vector( path.start.x, path.start.y, path.start.z )
		path.start 	= mover.GetOrigin()

		result = TraceHull( path.start, path.goal, mins, maxs, cloakedDrone, mask, TRACE_COLLISION_GROUP_NONE )
		//DebugDrawLine( path.start, path.goal, 255, 255, 0, true, 1.0 )
		if ( result.fraction < VALIDPATHFRAC )
			continue

		path.lastHeight = testHeight
		path.goalValid = true
		break
	}

	return path.goalValid
}

function CloakedDroneWarpOut( cloakedDrone, origin )
{
	local mover = cloakedDrone.GetParent()
	Assert( mover != null )

	if ( cloakedDrone.s.isHidden == false )
	{
		// only do this if we are not already hidden
		FadeOutSoundOnEntity( cloakedDrone, CLOAKED_DRONE_LOOPING_SFX, 0.5 )
		FadeOutSoundOnEntity( cloakedDrone, CLOAKED_DRONE_HOVER_LOOP_SFX, 0.5 )
		EmitSoundOnEntity( cloakedDrone, CLOAKED_DRONE_WARP_OUT_SFX )

		cloakedDrone.s.fx.Fire( "StopPlayEndCap" )
		cloakedDrone.SetTitle( "" )
		cloakedDrone.s.isHidden = true
		cloakedDrone.NotSolid()
		cloakedDrone.Minimap_Hide( TEAM_IMC, null )
		cloakedDrone.Minimap_Hide( TEAM_MILITIA, null )
		cloakedDrone.SetNoTarget( true )
		// let the beam fx end

		if ( "smokeEffect" in cloakedDrone.s )
		{
			cloakedDrone.s.smokeEffect.Kill()
			delete cloakedDrone.s.smokeEffect
		}

		wait 0.3	// wait a bit before hidding the done so that the fx looks better
		cloakedDrone.Hide()
		// SetCustomSmartAmmoTarget( cloakedDrone, false )
	}

	wait 2.0

	mover.SetMoveToPosition( origin )
	mover.SetOrigin( origin )
}

function CloakedDroneWarpIn( cloakedDrone, origin )
{
	local mover = cloakedDrone.GetParent()
	Assert( mover != null )

	mover.SetMoveToPosition( origin )
	mover.SetOrigin( origin )

	EmitSoundOnEntity( cloakedDrone, CLOAKED_DRONE_HOVER_LOOP_SFX )
	EmitSoundOnEntity( cloakedDrone, CLOAKED_DRONE_LOOPING_SFX )
	EmitSoundOnEntity( cloakedDrone, CLOAKED_DRONE_WARP_IN_SFX )

	cloakedDrone.Show()
	cloakedDrone.s.fx.Fire( "start" )
	cloakedDrone.SetTitle( "#NPC_CLOAK_DRONE" )
	cloakedDrone.s.isHidden = false
	cloakedDrone.Solid()
	cloakedDrone.Minimap_AlwaysShow( TEAM_IMC, null )
	cloakedDrone.Minimap_AlwaysShow( TEAM_MILITIA, null )
	cloakedDrone.SetNoTarget( false )

	// SetCustomSmartAmmoTarget( cloakedDrone, true )
}

function CreateDroneCloakBeam( cloakedDrone )
{
	local fx = PlayLoopFXOnEntity( FX_DRONE_CLOAK_BEAM, cloakedDrone, null, null, Vector( 90, 0, 0 ) )//, visibilityFlagOverride = null, visibilityFlagEntOverride = null )
	return fx
}


function FindBestCloakTarget( npcArray, origin )
{
    local selectedNPC = null
    local maxDist = 5000 * 5000
    local minDist = 1300 * 1300
    local highestScore = null

	foreach( npc in npcArray )
	{
		if ( !IsValid( npc ) || !IsAlive( npc ) )
			continue

		local score = 0
		local dist = DistanceSqr( npc.GetOrigin(), origin )
		
		// Operates within maxDist (5000 units)
		if ( dist <= maxDist )
		{
			// Closer targets get a higher base score
			score = GraphCapped( dist, minDist, maxDist, 1, 0 )

			// High priority for Titans
			if ( npc.IsTitan() )
			{
				score += 0.5 
			}
			
			local squadName = npc.kv.squadname
			if ( squadName != "" && squadName != null )
			{
				score += 0.2
			}
		}

		if ( highestScore == null || score > highestScore )
		{
			highestScore = score
			selectedNPC = npc
		}
	}

    return selectedNPC
}


function GetCloakTargetOrigin( npc )
{
	// returns the center of squad if the npc is in one
	// else returns a good spot to cloak a titan

	local origin

	if ( GetNPCSquadSize( npc.kv.squadname ) == 0 )
		origin = npc.GetOrigin() + npc.GetNPCVelocity()
	else
		origin = npc.GetSquadCentroid()

	Assert( origin.x < ( 16384 * 100 ) );

	// defensive hack
	if ( origin.x > ( 16384 * 100 ) )
		origin = npc.GetOrigin()

	return origin
}


function IsSquadCenterClose( npc, dist = 256 )
{
	// return true if there is no squad
	if ( GetNPCSquadSize( npc.kv.squadname ) == 0 )
		return true

	// return true if the squad isn't too spread out.
	if ( DistanceSqr( npc.GetSquadCentroid(), npc.GetOrigin() ) <= ( dist * dist ) )
		return true

	return false
}


function ApplyDroneCloak( drone, target )
{
    if ( !IsValid( target ) || !IsAlive( target ) )
        return


    if ( target.IsTitan() )
    {
        target.SetCanCloak( true )
        local soul = target.GetTitanSoul()
        if ( IsValid( soul ) )
        {
            soul.SetCloakDuration( 3.0, -1, 0 )
        }
    }

    target.SetCloakDuration( 3.0, -1, 0 ) 
}