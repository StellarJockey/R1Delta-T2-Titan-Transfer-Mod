function OnWeaponPrimaryAttack( attackParams )
{
	self.EmitWeaponNpcSound( LOUD_WEAPON_AI_SOUND_RADIUS_MP, 0.2 )
	self.FireWeaponBullet( attackParams.pos, attackParams.dir, 1, damageTypes.Electric | DF_STOPS_TITAN_REGEN )
}

function OnWeaponNpcPrimaryAttack( attackParams )
{
	self.EmitWeaponNpcSound( LOUD_WEAPON_AI_SOUND_RADIUS_MP, 0.2 )
	self.FireWeaponBullet( attackParams.pos, attackParams.dir, 1, damageTypes.Electric | DF_STOPS_TITAN_REGEN )
}

function OnWeaponStartZoomIn()
{
	HandleWeaponSoundZoomIn( self, "Weapon_R97.ADS_In" )
}

function OnWeaponStartZoomOut()
{
	HandleWeaponSoundZoomOut( self, "Weapon_R97.ADS_Out" )
}

function OnWeaponActivate( activateParams )
{
	local weaponOwner = self.GetWeaponOwner()
	if ( !IsValid_ThisFrame( weaponOwner ) )
		return

	if( weaponOwner.IsPlayer() )
	{
		SetLoopingWeaponSound_1p3p( "Weapon_R97.FirstShot", "Weapon_R97.Loop", "Weapon_R97.LoopEnd",
	                    	        "Weapon_R97.FirstShot_3P", "Weapon_R97.Loop_3P", "Weapon_R97.LoopEnd_3P" )
	}
	else
	{
		SetLoopingWeaponSound_1p3p( "Weapon_R97.FirstShot", "Weapon_R97.Loop", "Weapon_R97.LoopEnd",
	     	                      	"Weapon_R97.FirstShot_NPC", "Weapon_R97.Loop_NPC", "Weapon_R97.LoopEnd_NPC" )
	}
}

function OnWeaponDeactivate( deactivateParams )
{
	self.ClearLoopingWeaponSound()
}