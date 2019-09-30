#include <amxmodx>
#include <amxmisc>
#include <crxknives_const>
#include <cromchat>
#include <fakemeta>
#include <hamsandwich>
#include <nvault>

native crxranks_get_max_levels()
native crxranks_get_rank_by_level(level, buffer[], len)
native crxranks_get_user_level(id)
native crxranks_get_user_xp(id)

new const g_szNatives[][] =
{
	"crxranks_get_max_levels",
	"crxranks_get_rank_by_level",
	"crxranks_get_user_level",
	"crxranks_get_user_xp"
}

#if !defined m_pPlayer
const m_pPlayer = 41
#endif

#if !defined client_disconnected
	#define client_disconnected client_disconnect
#endif

new const PLUGIN_VERSION[] = "3.1.1"
const Float:DELAY_ON_CONNECT = 3.0

#if !defined MAX_AUTHID_LENGTH
const MAX_AUTHID_LENGTH = 35
#endif

#if !defined MAX_NAME_LENGTH
const MAX_NAME_LENGTH = 32
#endif

#if !defined MAX_PLAYERS
const MAX_PLAYERS = 32
#endif

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
	NAME[MAX_NAME_LENGTH],
	V_MODEL[CRXKNIVES_MAX_SOUND_LENGTH],
	P_MODEL[CRXKNIVES_MAX_SOUND_LENGTH],
	DEPLOY_SOUND[CRXKNIVES_MAX_SOUND_LENGTH],
	HIT_SOUND[CRXKNIVES_MAX_SOUND_LENGTH],
	HITWALL_SOUND[CRXKNIVES_MAX_SOUND_LENGTH],
	SLASH_SOUND[CRXKNIVES_MAX_SOUND_LENGTH],
	STAB_SOUND[CRXKNIVES_MAX_SOUND_LENGTH],
	SELECT_SOUND[CRXKNIVES_MAX_SOUND_LENGTH],
	FLAG,
	LEVEL,
	XP,
	SELECT_MESSAGES_NUM,
	bool:SHOW_RANK,
	bool:HAS_CUSTOM_SOUND,
	Array:SELECT_MESSAGES,
	Trie:ATTRIBUTES
}

enum _:CvarsReg
{
	cvar_km_open_at_spawn,
	cvar_km_save_choice,
	cvar_km_only_dead,
	cvar_km_select_message,
	cvar_km_knife_only_skills,
	cvar_km_admin_bypass
}

enum _:Cvars
{
	km_open_at_spawn,
	km_save_choice,
	km_only_dead,
	km_select_message,
	km_knife_only_skills,
	km_admin_bypass
}

new Array:g_aKnives,
	bool:g_bFirstTime[MAX_PLAYERS + 1],
	bool:g_bRankSystem,
	bool:g_bGetLevel,
	bool:g_bGetXP,
	g_eCvars[Cvars],
	g_eCvarsReg[CvarsReg],
	g_eKnife[MAX_PLAYERS + 1][Knives],
	g_szAuth[MAX_PLAYERS + 1][MAX_AUTHID_LENGTH],
	g_iKnife[MAX_PLAYERS + 1],
	g_fwdKnifeUpdated,
	g_fwdAttemptChange,
	g_iMenuFlags,
	g_iKnivesNum,
	g_iCallback,
	g_iVault

public plugin_init()
{
	register_plugin("Knife Models", PLUGIN_VERSION, "OciXCrom")
	register_cvar("CRXKnifeModels", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED)

	if(!g_iKnivesNum)
	{
		set_fail_state("No knives found in the configuration file.")
	}

	register_dictionary("KnifeModels.txt")

	RegisterHam(Ham_Spawn, "player", "OnPlayerSpawn", 1)
	register_forward(FM_EmitSound,	"OnEmitSound")
	RegisterHam(Ham_Item_Deploy, "weapon_knife", "OnSelectKnife", 1)

	register_clcmd("say /knife",       "Cmd_Knife")
	register_clcmd("say_team /knife",  "Cmd_Knife")
	register_clcmd("crxknives_select", "Cmd_Select", _, "<knife id>")

	g_fwdKnifeUpdated  = CreateMultiForward("crxknives_knife_updated",  ET_IGNORE, FP_CELL, FP_CELL, FP_CELL)
	g_fwdAttemptChange = CreateMultiForward("crxknives_attempt_change", ET_STOP,   FP_CELL, FP_CELL)

	g_iCallback = menu_makecallback("CheckKnifeAccess")

	g_eCvarsReg[cvar_km_open_at_spawn]     = register_cvar("km_open_at_spawn",     "0")
	g_eCvarsReg[cvar_km_save_choice]       = register_cvar("km_save_choice",       "1")
	g_eCvarsReg[cvar_km_only_dead]         = register_cvar("km_only_dead",         "0")
	g_eCvarsReg[cvar_km_select_message]    = register_cvar("km_select_message",    "1")
	g_eCvarsReg[cvar_km_knife_only_skills] = register_cvar("km_knife_only_skills", "1")
	g_eCvarsReg[cvar_km_admin_bypass]      = register_cvar("km_admin_bypass",      "0")
}

public plugin_precache()
{
	if(LibraryExists("crxranks", LibType_Library))
	{
		g_bRankSystem = true
	}

	g_aKnives = ArrayCreate(Knives)
	ReadFile()
}

public plugin_cfg()
{
	g_eCvars[km_save_choice]       = get_pcvar_num(g_eCvarsReg[cvar_km_save_choice])
	g_eCvars[km_open_at_spawn]     = get_pcvar_num(g_eCvarsReg[cvar_km_open_at_spawn])
	g_eCvars[km_only_dead]         = get_pcvar_num(g_eCvarsReg[cvar_km_only_dead])
	g_eCvars[km_select_message]    = get_pcvar_num(g_eCvarsReg[cvar_km_select_message])
	g_eCvars[km_knife_only_skills] = get_pcvar_num(g_eCvarsReg[cvar_km_knife_only_skills])
	g_eCvars[km_admin_bypass]      = get_pcvar_num(g_eCvarsReg[cvar_km_admin_bypass])

	if(g_eCvars[km_save_choice])
	{
		g_iVault = nvault_open("KnifeModels")
	}
}

public plugin_end()
{
	for(new eKnife[Knives], i; i < g_iKnivesNum; i++)
	{
		ArrayGetArray(g_aKnives, i, eKnife)
		ArrayDestroy(eKnife[SELECT_MESSAGES])
		TrieDestroy(eKnife[ATTRIBUTES])
	}

	ArrayDestroy(g_aKnives)

	if(g_eCvars[km_save_choice])
	{
		nvault_close(g_iVault)
	}
}

ReadFile()
{
	new szFilename[256]
	get_configsdir(szFilename, charsmax(szFilename))
	add(szFilename, charsmax(szFilename), "/KnifeModels.ini")
	new iFilePointer = fopen(szFilename, "rt")

	if(iFilePointer)
	{
		new szData[160], szKey[32], szValue[128], szSound[128], iMaxLevels
		new eKnife[Knives], bool:bCustom

		if(g_bRankSystem)
		{
			iMaxLevels = crxranks_get_max_levels()
		}

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
						{
							push_knife(eKnife)
						}

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
						eKnife[SELECT_SOUND][0] = EOS
						eKnife[FLAG] = ADMIN_ALL
						eKnife[HAS_CUSTOM_SOUND] = false
						eKnife[SELECT_MESSAGES_NUM] = 0
						eKnife[SELECT_MESSAGES] = _:ArrayCreate(CRXKNIVES_MAX_MESSAGE_LENGTH)
						eKnife[ATTRIBUTES] = _:TrieCreate()

						if(g_bRankSystem)
						{
							eKnife[LEVEL] = 0
							eKnife[SHOW_RANK] = false
							eKnife[XP] = 0
						}

						static const ATTRIBUTE_NAME[] = "NAME"
						TrieSetString(eKnife[ATTRIBUTES], ATTRIBUTE_NAME, szData)
					}
					else continue
				}
				default:
				{
					strtok(szData, szKey, charsmax(szKey), szValue, charsmax(szValue), '=')
					trim(szKey); trim(szValue)
					bCustom = true

					TrieSetString(eKnife[ATTRIBUTES], szKey, szValue)

					if(equal(szKey, "FLAG"))
					{
						eKnife[FLAG] = read_flags(szValue)
						g_iMenuFlags |= eKnife[FLAG]
					}
					else if(equal(szKey, "LEVEL") && g_bRankSystem)
					{
						eKnife[LEVEL] = clamp(str_to_num(szValue), 0, iMaxLevels)

						if(!g_bGetLevel)
						{
							g_bGetLevel = true
						}
					}
					else if(equal(szKey, "SHOW_RANK") && g_bRankSystem)
					{
						eKnife[SHOW_RANK] = _:clamp(str_to_num(szValue), false, true)
					}
					else if(equal(szKey, "XP") && g_bRankSystem)
					{
						eKnife[XP] = _:clamp(str_to_num(szValue), 0)

						if(!g_bGetXP)
						{
							g_bGetXP = true
						}
					}
					else if(equal(szKey, "V_MODEL"))
					{
						copy(eKnife[V_MODEL], charsmax(eKnife[V_MODEL]), szValue)
					}
					else if(equal(szKey, "P_MODEL"))
					{
						copy(eKnife[P_MODEL], charsmax(eKnife[P_MODEL]), szValue)
					}
					else if(equal(szKey, "DEPLOY_SOUND"))
					{
						copy(eKnife[DEPLOY_SOUND], charsmax(eKnife[DEPLOY_SOUND]), szValue)
					}
					else if(equal(szKey, "HIT_SOUND"))
					{
						copy(eKnife[HIT_SOUND], charsmax(eKnife[HIT_SOUND]), szValue)
					}
					else if(equal(szKey, "HITWALL_SOUND"))
					{
						copy(eKnife[HITWALL_SOUND], charsmax(eKnife[HITWALL_SOUND]), szValue)
					}
					else if(equal(szKey, "SLASH_SOUND"))
					{
						copy(eKnife[SLASH_SOUND], charsmax(eKnife[SLASH_SOUND]), szValue)
					}
					else if(equal(szKey, "STAB_SOUND"))
					{
						copy(eKnife[STAB_SOUND], charsmax(eKnife[STAB_SOUND]), szValue)
					}
					else if(equal(szKey, "SELECT_SOUND"))
					{
						bCustom = false
						copy(eKnife[SELECT_SOUND], charsmax(eKnife[SELECT_SOUND]), szValue)
					}
					else if(equal(szKey, "SELECT_MESSAGE"))
					{
						ArrayPushString(eKnife[SELECT_MESSAGES], szValue)
						eKnife[SELECT_MESSAGES_NUM]++
					}
					else continue

					static const szModelArg[] = "_MODEL"
					static const szSoundArg[] = "_SOUND"

					if(contain(szKey, szModelArg) != -1)
					{
						if(!file_exists(szValue))
						{
							log_amx("ERROR: model ^"%s^" not found!", szValue)
						}
						else
						{
							precache_model(szValue)
						}
					}
					else if(contain(szKey, szSoundArg) != -1)
					{
						formatex(szSound, charsmax(szSound), "sound/%s", szValue)

						if(!file_exists(szSound))
						{
							log_amx("ERROR: sound ^"%s^" not found!", szSound)
						}
						else
						{
							precache_sound(szValue)
						}

						if(bCustom)
						{
							eKnife[HAS_CUSTOM_SOUND] = true
						}
					}
				}
			}
		}

		if(g_iKnivesNum)
		{
			push_knife(eKnife)
		}

		fclose(iFilePointer)
	}
}

public client_connect(id)
{
	g_bFirstTime[id] = true
	ArrayGetArray(g_aKnives, 0, g_eKnife[id])
	g_iKnife[id] = 0

	new iReturn
	ExecuteForward(g_fwdKnifeUpdated, iReturn, id, g_iKnife[id], true)

	if(g_eCvars[km_save_choice])
	{
		get_user_authid(id, g_szAuth[id], charsmax(g_szAuth[]))
		set_task(DELAY_ON_CONNECT, "load_data", id)
	}
}

public client_disconnected(id)
{
	if(g_eCvars[km_save_choice])
	{
		use_vault(id, true)
	}
}

public OnEmitSound(id, iChannel, const szSample[])
{
	if(!is_user_connected(id) || !g_eKnife[id][HAS_CUSTOM_SOUND] || !is_knife_sound(szSample))
	{
		return FMRES_IGNORED
	}

	switch(detect_knife_sound(szSample))
	{
		case SOUND_DEPLOY: 		if(g_eKnife[id][DEPLOY_SOUND][0]) 		{ play_knife_sound(id, g_eKnife[id][DEPLOY_SOUND][0]);      return FMRES_SUPERCEDE; }
		case SOUND_HIT: 		if(g_eKnife[id][HIT_SOUND][0]) 			{ play_knife_sound(id, g_eKnife[id][HIT_SOUND][0]);         return FMRES_SUPERCEDE; }
		case SOUND_HITWALL:		if(g_eKnife[id][HITWALL_SOUND][0]) 		{ play_knife_sound(id, g_eKnife[id][HITWALL_SOUND][0]);     return FMRES_SUPERCEDE; }
		case SOUND_SLASH: 		if(g_eKnife[id][SLASH_SOUND][0]) 		{ play_knife_sound(id, g_eKnife[id][SLASH_SOUND][0]);       return FMRES_SUPERCEDE; }
		case SOUND_STAB: 		if(g_eKnife[id][STAB_SOUND][0]) 		{ play_knife_sound(id, g_eKnife[id][STAB_SOUND][0]);        return FMRES_SUPERCEDE; }
	}

	return FMRES_IGNORED
}

public Cmd_Knife(id)
{
	if(g_eCvars[km_only_dead] && is_user_alive(id))
	{
		CC_SendMessage(id, "%L %L", id, "KM_CHAT_PREFIX", id, "KM_ONLY_DEAD")
		return PLUGIN_HANDLED
	}

	static eKnife[Knives]
	new szTitle[128], szItem[128], iLevel, iXP
	formatex(szTitle, charsmax(szTitle), "%L", id, "KM_MENU_TITLE")

	if(g_bGetLevel)
	{
		iLevel = crxranks_get_user_level(id)
	}

	if(g_bGetXP)
	{
		iXP = crxranks_get_user_xp(id)
	}

	new iMenu = menu_create(szTitle, "MenuHandler")

	for(new iFlags = get_user_flags(id), i; i < g_iKnivesNum; i++)
	{
		ArrayGetArray(g_aKnives, i, eKnife)
		copy(szItem, charsmax(szItem), eKnife[NAME])

		if(g_bRankSystem)
		{
			if(eKnife[LEVEL] && iLevel < eKnife[LEVEL])
			{
				if(eKnife[SHOW_RANK])
				{
					static szRank[32]
					crxranks_get_rank_by_level(eKnife[LEVEL], szRank, charsmax(szRank))
					format(szItem, charsmax(szItem), "%s %L", szItem, id, "KM_MENU_RANK", szRank)
				}
				else
				{
					format(szItem, charsmax(szItem), "%s %L", szItem, id, "KM_MENU_LEVEL", eKnife[LEVEL])
				}
			}

			if(eKnife[XP] && iXP < eKnife[XP])
			{
				format(szItem, charsmax(szItem), "%s %L", szItem, id, "KM_MENU_XP", eKnife[XP])
			}
		}

		if(eKnife[FLAG] != ADMIN_ALL && !(iFlags & eKnife[FLAG]))
		{
			format(szItem, charsmax(szItem), "%s %L", szItem, id, "KM_MENU_VIP_ONLY")
		}

		if(g_iKnife[id] == i)
		{
			format(szItem, charsmax(szItem), "%s %L", szItem, id, "KM_MENU_SELECTED")
		}

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

public Cmd_Select(id, iLevel, iCid)
{
	if(!cmd_access(id, iLevel, iCid, 2))
	{
		return PLUGIN_HANDLED
	}

	if(g_eCvars[km_only_dead] && is_user_alive(id))
	{
		CC_SendMessage(id, "%L %L", id, "KM_CHAT_PREFIX", id, "KM_ONLY_DEAD")
		return PLUGIN_HANDLED
	}

	new szKnife[4]
	read_argv(1, szKnife, charsmax(szKnife))

	new iKnife = str_to_num(szKnife)

	if(!is_knife_valid(iKnife))
	{
		console_print(id, "%l", "KM_INVALID_KNIFE", g_iKnivesNum - 1)
		return PLUGIN_HANDLED
	}

	if(!has_knife_access(id, iKnife))
	{
		console_print(id, "%l", "KM_NO_ACCESS")
		return PLUGIN_HANDLED
	}

	select_knife(id, iKnife)
	return PLUGIN_HANDLED
}

public MenuHandler(id, iMenu, iItem)
{
	if(g_eCvars[km_only_dead] && is_user_alive(id))
	{
		CC_SendMessage(id, "%L %L", id, "KM_CHAT_PREFIX", id, "KM_ONLY_DEAD")
		goto @MENU_DESTROY
	}

	if(!is_user_connected(id))
	{
		goto @MENU_DESTROY
	}

	if(iItem != MENU_EXIT)
	{
		select_knife(id, iItem)
	}

	@MENU_DESTROY:
	menu_destroy(iMenu)
	return PLUGIN_HANDLED
}

select_knife(id, iKnife)
{
	new iReturn
	ExecuteForward(g_fwdAttemptChange, iReturn, id, iKnife)

	if(iReturn == PLUGIN_HANDLED)
	{
		return
	}

	g_iKnife[id] = iKnife
	ArrayGetArray(g_aKnives, iKnife, g_eKnife[id])
	ExecuteForward(g_fwdKnifeUpdated, iReturn, id, iKnife, false)

	if(is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
	{
		refresh_knife_model(id)
	}

	if(g_eCvars[km_select_message])
	{
		CC_SendMessage(id, "%L %L", id, "KM_CHAT_PREFIX", id, "KM_CHAT_SELECTED", g_eKnife[id][NAME])
	}

	if(g_eKnife[id][SELECT_MESSAGES_NUM])
	{
		for(new i; i < g_eKnife[id][SELECT_MESSAGES_NUM]; i++)
		{
			CC_SendMessage(id, "%a", ArrayGetStringHandle(g_eKnife[id][SELECT_MESSAGES], i))
		}
	}

	if(g_eKnife[id][SELECT_SOUND][0])
	{
		play_knife_sound(id, g_eKnife[id][SELECT_SOUND])
	}
}

public load_data(id)
{
	if(is_user_connected(id))
	{
		use_vault(id, false)
	}
}

public CheckKnifeAccess(id, iMenu, iItem)
{
	return ((g_iKnife[id] == iItem) || !has_knife_access(id, iItem)) ? ITEM_DISABLED : ITEM_ENABLED
}

public OnPlayerSpawn(id)
{
	if(is_user_alive(id) && g_eCvars[km_open_at_spawn] && !g_iKnife[id] && g_bFirstTime[id] && (g_iMenuFlags & ADMIN_USER || get_user_flags(id) & g_iMenuFlags))
	{
		g_bFirstTime[id] = false
		Cmd_Knife(id)
	}
}

public OnSelectKnife(iEnt)
{
	new id = get_pdata_cbase(iEnt, m_pPlayer, 4)

	if(is_user_connected(id))
	{
		refresh_knife_model(id)
	}
}

refresh_knife_model(const id)
{
	set_pev(id, pev_viewmodel2, g_eKnife[id][V_MODEL])
	set_pev(id, pev_weaponmodel2, g_eKnife[id][P_MODEL])
}

push_knife(eKnife[Knives])
{
	if(!eKnife[V_MODEL][0])
	{
		copy(eKnife[V_MODEL], charsmax(eKnife[V_MODEL]), CRXKNIVES_DEFAULT_V)
	}

	if(!eKnife[P_MODEL][0])
	{
		copy(eKnife[P_MODEL], charsmax(eKnife[P_MODEL]), CRXKNIVES_DEFAULT_P)
	}

	if(!eKnife[FLAG])
	{
		g_iMenuFlags |= ADMIN_USER
	}

	ArrayPushArray(g_aKnives, eKnife)
}

bool:has_knife_access(const id, const iKnife)
{
	static eKnife[Knives]
	ArrayGetArray(g_aKnives, iKnife, eKnife)

	if(eKnife[FLAG] != ADMIN_ALL)
	{
		if(get_user_flags(id) & eKnife[FLAG])
		{
			if(g_eCvars[km_admin_bypass])
			{
				return true
			}
		}
		else
		{
			return false
		}
	}

	if(g_bRankSystem)
	{
		if(eKnife[LEVEL] && crxranks_get_user_level(id) < eKnife[LEVEL])
		{
			return false
		}

		if(eKnife[XP] && crxranks_get_user_xp(id) < eKnife[XP])
		{
			return false
		}
	}

	return true
}

bool:is_knife_sound(const szSample[])
{
	return bool:equal(szSample[8], "kni", 3)
}

detect_knife_sound(const szSample[])
{
	static iSound
	iSound = SOUND_NONE

	if(equal(szSample, "weapons/knife_deploy1.wav"))
	{
		iSound = SOUND_DEPLOY
	}
	else if(equal(szSample[14], "hit", 3))
	{
		iSound = szSample[17] == 'w' ? SOUND_HITWALL : SOUND_HIT
	}
	else if(equal(szSample[14], "sla", 3))
	{
		iSound = SOUND_SLASH
	}
	else if(equal(szSample[14], "sta", 3))
	{
		iSound = SOUND_STAB
	}

	return iSound
}

use_vault(const id, const bool:bSave)
{
	if(bSave)
	{
		new szData[4]
		num_to_str(g_iKnife[id], szData, charsmax(szData))
		nvault_set(g_iVault, g_szAuth[id], szData)
	}
	else
	{
		new iKnife
		iKnife = nvault_get(g_iVault, g_szAuth[id])

		if(!is_knife_valid(iKnife))
		{
			iKnife = 0
		}
		else if(has_knife_access(id, iKnife))
		{
			g_iKnife[id] = iKnife

			new iReturn
			ArrayGetArray(g_aKnives, iKnife, g_eKnife[id])
			ExecuteForward(g_fwdKnifeUpdated, iReturn, id, iKnife, false)

			if(is_user_alive(id) && get_user_weapon(id) == CSW_KNIFE)
			{
				refresh_knife_model(id)
			}
		}
	}
}

play_knife_sound(const id, const szSound[])
{
	engfunc(EngFunc_EmitSound, id, CHAN_AUTO, szSound, 1.0, ATTN_NORM, 0, PITCH_NORM)
}

bool:is_knife_valid(const iKnife)
{
	return 0 <= iKnife < g_iKnivesNum
}

public plugin_natives()
{
	register_library("crxknives")
	register_native("crxknives_can_use_skill",       "_crxknives_can_use_skill")
	register_native("crxknives_get_attribute_int",   "_crxknives_get_attribute_int")
	register_native("crxknives_get_attribute_float", "_crxknives_get_attribute_float")
	register_native("crxknives_get_attribute_str",   "_crxknives_get_attribute_str")
	register_native("crxknives_get_knives_num",      "_crxknives_get_knives_num")
	register_native("crxknives_get_user_knife",      "_crxknives_get_user_knife")
	register_native("crxknives_has_knife_access",    "_crxknives_has_knife_access")
	register_native("crxknives_is_knife_valid",      "_crxknives_is_knife_valid")
	set_native_filter("native_filter")
}

public native_filter(const szNative[], id, iTrap)
{
	if(!iTrap)
	{
		static i

		for(i = 0; i < sizeof(g_szNatives); i++)
		{
			if(equal(szNative, g_szNatives[i]))
			{
				return PLUGIN_HANDLED
			}
		}
	}

	return PLUGIN_CONTINUE
}

public bool:_crxknives_can_use_skill(iPlugin, iParams)
{
	return !g_eCvars[km_knife_only_skills] || (get_user_weapon(get_param(1)) == CSW_KNIFE)
}

public bool:_crxknives_get_attribute_int(iPlugin, iParams)
{
	static szAttribute[MAX_NAME_LENGTH], szValue[CRXKNIVES_MAX_ATTRIBUTE_LENGTH], id
	get_string(2, szAttribute, charsmax(szAttribute))
	id = get_param(1)

	if(!get_param(4))
	{
		if(!is_knife_valid(id))
		{
			return false
		}

		static eKnife[Knives]
		ArrayGetArray(g_aKnives, id, eKnife)

		if(!TrieKeyExists(eKnife[ATTRIBUTES], szAttribute))
		{
			return false
		}

		TrieGetString(eKnife[ATTRIBUTES], szAttribute, szValue, charsmax(szValue))
		goto @SET_ATTRIBUTE
	}

	if(!TrieKeyExists(g_eKnife[id][ATTRIBUTES], szAttribute))
	{
		return false
	}

	TrieGetString(g_eKnife[id][ATTRIBUTES], szAttribute, szValue, charsmax(szValue))

	@SET_ATTRIBUTE:
	set_param_byref(3, str_to_num(szValue))
	return true
}

public bool:_crxknives_get_attribute_float(iPlugin, iParams)
{
	static szAttribute[MAX_NAME_LENGTH], szValue[CRXKNIVES_MAX_ATTRIBUTE_LENGTH], id
	get_string(2, szAttribute, charsmax(szAttribute))
	id = get_param(1)

	if(!get_param(4))
	{
		if(!is_knife_valid(id))
		{
			return false
		}

		static eKnife[Knives]
		ArrayGetArray(g_aKnives, id, eKnife)

		if(!TrieKeyExists(eKnife[ATTRIBUTES], szAttribute))
		{
			return false
		}

		TrieGetString(eKnife[ATTRIBUTES], szAttribute, szValue, charsmax(szValue))
		goto @SET_ATTRIBUTE
	}

	if(!TrieKeyExists(g_eKnife[id][ATTRIBUTES], szAttribute))
	{
		return false
	}

	TrieGetString(g_eKnife[id][ATTRIBUTES], szAttribute, szValue, charsmax(szValue))

	@SET_ATTRIBUTE:
	set_float_byref(3, str_to_float(szValue))
	return true
}

public bool:_crxknives_get_attribute_str(iPlugin, iParams)
{
	static szAttribute[MAX_NAME_LENGTH], szValue[CRXKNIVES_MAX_ATTRIBUTE_LENGTH], id
	get_string(2, szAttribute, charsmax(szAttribute))
	id = get_param(1)

	if(!get_param(5))
	{
		if(!is_knife_valid(id))
		{
			return false
		}

		static eKnife[Knives]
		ArrayGetArray(g_aKnives, id, eKnife)

		if(!TrieKeyExists(eKnife[ATTRIBUTES], szAttribute))
		{
			return false
		}

		TrieGetString(eKnife[ATTRIBUTES], szAttribute, szValue, charsmax(szValue))
		goto @SET_ATTRIBUTE
	}

	if(!TrieKeyExists(g_eKnife[id][ATTRIBUTES], szAttribute))
	{
		return false
	}

	TrieGetString(g_eKnife[id][ATTRIBUTES], szAttribute, szValue, charsmax(szValue))

	@SET_ATTRIBUTE:
	set_string(3, szValue, get_param(4))
	return true
}

public _crxknives_get_knives_num(iPlugin, iParams)
{
	return g_iKnivesNum
}

public _crxknives_get_user_knife(iPlugin, iParams)
{
	return g_iKnife[get_param(1)]
}

public bool:_crxknives_has_knife_access(iPlugin, iParams)
{
	return has_knife_access(get_param(1), get_param(2))
}

public bool:_crxknives_is_knife_valid(iPlugin, iParams)
{
	return is_knife_valid(get_param(1))
}