function main()
{
	if ( IsLobby() )
		return

	AddSpawnCallback( "npc_soldier", EnableRebreatherMasks )
	AddCallback_OnPlayerRespawned( EnableRebreatherMasks )
}

function EnableRebreatherMasks( entity )
{
	// Masks are already forced on in Outpost 207
	if ( GetMapName() == "mp_outpost_207" )
		return

	// Outpost 207 takes place on a moon. Moons don't have much atmosphere (aside from Staurn's moon Titan, funnily enough)
	// Sandtrap takes place on a moon similar to Outpost 207
	// Airbase is explicitly stated to be one of the moons of Demeter
	if ( GetMapName() == "mp_sandtrap" ||  GetMapName() == "mp_airbase" )
	{
		SetRebreatherMaskVisible( entity, true )
		return
	}
}

main()