#include <amxmodx>
#include <amxmisc>
#include <cromchat>
#include <fakemeta>
#include <hamsandwich>

native crxranks_get_user_level(id)

#define PLUGIN_VERSION "2.3"
#define DEFAULT_V "models/v_knife.mdl"
#define DEFAULT_P "models/p_knife.mdl"

enum
{
	SOUND_NONE = 0,
	SOUND_DEPLOY,
	SOUND_HIT,
	SOUND_HITWALL,
	SOUND_SLASH,
	SOUND_STAB
}

enum _:Knives
{
	NAME[32],
	V_MODEL[128],
	P_MODEL[128],
	DEPLOY_SOUND[128],
	HIT_SOUND[128],
	HITWALL_SOUND[128],
	SLASH_SOUND[128],
	STAB_SOUND[128],
	FLAG,
	LEVEL,
	bool:HAS_CUSTOM_SOUND
}

new Array:g_aKnives,
	bool:g_bFirstTime[33],
	bool:g_bRankSystem,
	g_eKnife[33][Knives],
	g_iKnife[33],
	g_iCallback,
	g_pAtSpawn,
	g_iKnivesNum

public plugin_init()
{
	register_plugin("Knife Models", PLUGIN_VERSION, "OciXCrom")
	register_cvar("CRXKnifeModels", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED)
	
	if(!g_iKnivesNum)
		set_fail_state("No knives found in the configuration file.")
	
	register_dictionary("KnifeModels.txt")
	
	RegisterHam(Ham_Item_Deploy, "weapon_knife", "OnSelectKnife", 1)
	RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn", 1)
	register_forward(FM_EmitSound,	"OnEmitSound")
	
	register_clcmd("say /knife", "ShowMenu")
	register_clcmd("say_team /knife", "ShowMenu")
	
	g_iCallback = menu_makecallback("CheckKnifeAccess")
	g_pAtSpawn = register_cvar("km_open_at_spawn", "0")
}

public plugin_precache()
{
	if(LibraryExists("crxranks", LibType_Library))
		g_bRankSystem = true
		
	g_aKnives = ArrayCreate(Knives)
	ReadFile()
}

public plugin_natives()
	set_native_filter("native_filter")
	
public native_filter(const szNative[], id, iTrap)
	return (!iTrap && equal(szNative, "crxranks_get_user_level")) ? PLUGIN_HANDLED : PLUGIN_CONTINUE
	
public plugin_end()
	ArrayDestroy(g_aKnives)

ReadFile()
{
	new szConfigsName[256], szFilename[256]
	get_configsdir(szConfigsName, charsmax(szConfigsName))
	formatex(szFilename, charsmax(szFilename), "%s/KnifeModels.ini", szConfigsName)
	new iFilePointer = fopen(szFilename, "rt")
	
	if(iFilePointer)
	{
		new szData[160], szKey[32], szValue[128]
		new eKnife[Knives]
		
		while(!feof(iFilePointer))
		{
			fgets(iFilePointer, szData, charsmax(szData))
			trim(szData)
			
			switch(szData[0])
			{
				case EOS, '#', ';': continue
				case '[':
				{
					if(szData[strlen(szData) - 1] == ']')
					{
						if(g_iKnivesNum)
							PushKnife(eKnife)
							
						g_iKnivesNum++
						replace(szData, charsmax(szData), "[", "")
						replace(szData, charsmax(szData), "]", "")
						copy(eKnife[NAME], charsmax(eKnife[NAME]), szData)
						
						eKnife[V_MODEL][0] = EOS
						eKnife[P_MODEL][0] = EOS
						eKnife[DEPLOY_SOUND][0] = EOS
						eKnife[HIT_SOUND][0] = EOS
						eKnife[HITWALL_SOUND][0] = EOS
						eKnife[SLASH_SOUND][0] = EOS
						eKnife[STAB_SOUND][0] = EOS
						eKnife[FLAG] = ADMIN_ALL
						eKnife[HAS_CUSTOM_SOUND] = false
						
						if(g_bRankSystem)
							eKnife[LEVEL] = 0
					}
					else continue
				}
				default:
				{
					strtok(szData, szKey, charsmax(szKey), szValue, charsmax(szValue), '=')
					trim(szKey); trim(szValue)
					
					if(equal(szKey, "FLAG"))
						eKnife[FLAG] = read_flags(szValue)
					else if(equal(szKey, "LEVEL") && g_bRankSystem)
						eKnife[LEVEL] = str_to_num(szValue)
					else if(equal(szKey, "V_MODEL"))
						copy(eKnife[V_MODEL], charsmax(eKnife[V_MODEL]), szValue)
					else if(equal(szKey, "P_MODEL"))
						copy(eKnife[P_MODEL], charsmax(eKnife[P_MODEL]), szValue)
					else if(equal(szKey, "DEPLOY_SOUND"))
						copy(eKnife[DEPLOY_SOUND], charsmax(eKnife[DEPLOY_SOUND]), szValue)
					else if(equal(szKey, "HIT_SOUND"))
						copy(eKnife[HIT_SOUND], charsmax(eKnife[HIT_SOUND]), szValue)
					else if(equal(szKey, "HITWALL_SOUND"))
						copy(eKnife[HITWALL_SOUND], charsmax(eKnife[HITWALL_SOUND]), szValue)
					else if(equal(szKey, "SLASH_SOUND"))
						copy(eKnife[SLASH_SOUND], charsmax(eKnife[SLASH_SOUND]), szValue)
					else if(equal(szKey, "STAB_SOUND"))
						copy(eKnife[STAB_SOUND], charsmax(eKnife[STAB_SOUND]), szValue)
					else continue
					
					static const szModelArg[] = "_MODEL"
					static const szSoundArg[] = "_SOUND"
					
					if(contain(szKey, szModelArg) != -1)
						precache_model(szValue)
					else if(contain(szKey, szSoundArg) != -1)
					{
						eKnife[HAS_CUSTOM_SOUND] = true
						precache_sound(szValue)
					}
				}
			}
		}
		
		if(g_iKnivesNum)
			PushKnife(eKnife)
		
		fclose(iFilePointer)
	}
}

public client_putinserver(id)
{
	g_bFirstTime[id] = true
	ArrayGetArray(g_aKnives, 0, g_eKnife[id])
	g_iKnife[id] = 0
}

public OnEmitSound(id, iChannel, const szSample[])
{
	if(!is_user_connected(id) || !g_eKnife[id][HAS_CUSTOM_SOUND] || !IsKnifeSound(szSample))
		return FMRES_IGNORED
	
	switch(DetectKnifeSound(szSample))
	{
		case SOUND_DEPLOY: 		if(g_eKnife[id][DEPLOY_SOUND][0]) 		{ PlayKnifeSound(id, g_eKnife[id][DEPLOY_SOUND][0]); 	return FMRES_SUPERCEDE; }
		case SOUND_HIT: 		if(g_eKnife[id][HIT_SOUND][0]) 			{ PlayKnifeSound(id, g_eKnife[id][HIT_SOUND][0]); 		return FMRES_SUPERCEDE; }
		case SOUND_HITWALL:		if(g_eKnife[id][HITWALL_SOUND][0]) 		{ PlayKnifeSound(id, g_eKnife[id][HITWALL_SOUND][0]); 	return FMRES_SUPERCEDE; }
		case SOUND_SLASH: 		if(g_eKnife[id][SLASH_SOUND][0]) 		{ PlayKnifeSound(id, g_eKnife[id][SLASH_SOUND][0]);		return FMRES_SUPERCEDE; }
		case SOUND_STAB: 		if(g_eKnife[id][STAB_SOUND][0]) 		{ PlayKnifeSound(id, g_eKnife[id][STAB_SOUND][0]); 		return FMRES_SUPERCEDE; }
	}
	
	return FMRES_IGNORED
}

public ShowMenu(id)
{
	static eKnife[Knives]
	new szTitle[128], szItem[128], iLevel
	formatex(szTitle, charsmax(szTitle), "%L", id, "KM_MENU_TITLE")

	if(g_bRankSystem)
		iLevel = crxranks_get_user_level(id)
		
	new iMenu = menu_create(szTitle, "MenuHandler")
	
	for(new iFlags = get_user_flags(id), i; i < g_iKnivesNum; i++)
	{
		ArrayGetArray(g_aKnives, i, eKnife)
		copy(szItem, charsmax(szItem), eKnife[NAME])
		
		if(g_bRankSystem && eKnife[LEVEL] && iLevel < eKnife[LEVEL])
			format(szItem, charsmax(szItem), "%s %L", szItem, id, "KM_MENU_LEVEL", eKnife[LEVEL])
		
		if(eKnife[FLAG] != ADMIN_ALL && !(iFlags & eKnife[FLAG]))
			format(szItem, charsmax(szItem), "%s %L", szItem, id, "KM_MENU_VIP_ONLY")
			
		if(g_iKnife[id] == i)
			format(szItem, charsmax(szItem), "%s %L", szItem, id, "KM_MENU_SELECTED")
		
		menu_additem(iMenu, szItem, eKnife[NAME], eKnife[FLAG], g_iCallback)
	}
	
	if(menu_pages(iMenu) > 1)
	{
		formatex(szItem, charsmax(szItem), "%s%L", szTitle, id, "KM_MENU_TITLE_PAGE")
		menu_setprop(iMenu, MPROP_TITLE, szItem)
	}
		
	menu_display(id, iMenu)
	return PLUGIN_HANDLED
}

public MenuHandler(id, iMenu, iItem)
{
	if(iItem != MENU_EXIT)
	{
		g_iKnife[id] = iItem
		ArrayGetArray(g_aKnives, iItem, g_eKnife[id])
		
		if(is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
			RefreshKnifeModel(id)
		
		new szName[32], iUnused
		menu_item_getinfo(iMenu, iItem, iUnused, szName, charsmax(szName), .callback = iUnused)
		CC_SendMessage(id, "%L %L", id, "KM_CHAT_PREFIX", id, "KM_CHAT_SELECTED", szName)
	}
	
	menu_destroy(iMenu)
	return PLUGIN_HANDLED
}

public CheckKnifeAccess(id, iMenu, iItem)
{
	if(g_iKnife[id] == iItem)
		return ITEM_DISABLED
		
	static eKnife[Knives]
	ArrayGetArray(g_aKnives, iItem, eKnife)
	
	if(g_bRankSystem && eKnife[LEVEL] && crxranks_get_user_level(id) < eKnife[LEVEL])
		return ITEM_DISABLED
		
	if(eKnife[FLAG] != ADMIN_ALL && !(get_user_flags(id) & eKnife[FLAG]))
		return ITEM_DISABLED
		
	return ITEM_ENABLED
}

public OnPlayerSpawn(id)
{
	if(is_user_alive(id) && get_pcvar_num(g_pAtSpawn) && !g_iKnife[id] && g_bFirstTime[id])
	{
		g_bFirstTime[id] = false
		ShowMenu(id)
	}
}

public OnSelectKnife(iEnt)
{
	new id = pev(iEnt, pev_owner)
	
	if(is_user_connected(id))
		RefreshKnifeModel(id)
}

RefreshKnifeModel(id)
{
	set_pev(id, pev_viewmodel2, g_eKnife[id][V_MODEL])
	set_pev(id, pev_weaponmodel2, g_eKnife[id][P_MODEL])
}

PushKnife(eKnife[Knives])
{
	if(!eKnife[V_MODEL][0])
		copy(eKnife[V_MODEL], charsmax(eKnife[V_MODEL]), DEFAULT_V)
		
	if(!eKnife[P_MODEL][0])
		copy(eKnife[P_MODEL], charsmax(eKnife[P_MODEL]), DEFAULT_P)
		
	ArrayPushArray(g_aKnives, eKnife)
}

bool:IsKnifeSound(const szSample[])
	return bool:equal(szSample[8], "kni", 3)

DetectKnifeSound(const szSample[])
{
	static iSound
	iSound = SOUND_NONE
	
	if(equal(szSample, "weapons/knife_deploy1.wav"))
		iSound = SOUND_DEPLOY
	else if(equal(szSample[14], "hit", 3))
		iSound = szSample[17] == 'w' ? SOUND_HITWALL : SOUND_HIT
	else if(equal(szSample[14], "sla", 3))
		iSound = SOUND_SLASH
	else if(equal(szSample[14], "sta", 3))
		iSound = SOUND_STAB
		
	return iSound
}

PlayKnifeSound(id, const szSound[])
	engfunc(EngFunc_EmitSound, id, CHAN_AUTO, szSound, 1.0, ATTN_NORM, 0, PITCH_NORM)