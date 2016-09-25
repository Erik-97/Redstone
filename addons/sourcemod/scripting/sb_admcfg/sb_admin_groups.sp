// *************************************************************************
//  This file is part of sb_admcfg.
//
//  sb_admcfg is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, per version 3 of the License.
//  
//  sb_admcfg is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//  
//  You should have received a copy of the GNU General Public License
//  along with sb_admcfg. If not, see <http://www.gnu.org/licenses/>.
//
//  This file incorporates work covered by the following copyright(s):   
//
//   SourceMod Admin File Reader Plugin
//   Copyright (C) 2004-2008 AlliedModders LLC
//   Licensed under GNU GPL version 3
//   Page: <http://www.sourcemod.net/>
//
//   SourceBans++
//   Copyright (C) 2014-2016 Sarabveer Singh <me@sarabveer.me
//   Licensed under GNU GPL version 3, or later.
//   Page: <https://forums.alliedmods.net/showthread.php?t=263735> - <https://github.com/sbpp/sourcebans-pp>
// *************************************************************************

enum GroupState
{
	GroupState_None, 
	GroupState_Groups, 
	GroupState_InGroup, 
	GroupState_Overrides, 
}

enum GroupPass
{
	GroupPass_Invalid, 
	GroupPass_First, 
	GroupPass_Second, 
}

static SMCParser g_hGroupParser;
static GroupId g_CurGrp = INVALID_GROUP_ID;
static GroupState g_GroupState = GroupState_None;
static GroupPass g_GroupPass = GroupPass_Invalid;
static bool g_NeedReparse = false;

public SMCResult ReadGroups_NewSection(SMCParser smc, const char[] name, bool opt_quotes)
{
	if (g_IgnoreLevel)
	{
		g_IgnoreLevel++;
		return SMCParse_Continue;
	}
	
	if (g_GroupState == GroupState_None)
	{
		if (StrEqual(name, "Groups", false))
			g_GroupState = GroupState_Groups;
		else 
			g_IgnoreLevel++;
	}
	
	else if (g_GroupState == GroupState_Groups) 
	{
		if ((g_CurGrp = CreateAdmGroup(name)) == INVALID_GROUP_ID)
			g_CurGrp = FindAdmGroup(name);
			
		g_GroupState = GroupState_InGroup;
	} 
	
	else if (g_GroupState == GroupState_InGroup) 
	{
		if (StrEqual(name, "Overrides", false))
			g_GroupState = GroupState_Overrides;
		else 
			g_IgnoreLevel++;
	} 
	
	else 
		g_IgnoreLevel++;
	
	
	return SMCParse_Continue;
}

public SMCResult ReadGroups_KeyValue(	SMCParser smc, 
					const char[] key, 
					const char[] value, 
					bool key_quotes, 
					bool value_quotes)
{
	if (g_CurGrp == INVALID_GROUP_ID || g_IgnoreLevel)
		return SMCParse_Continue;

	AdminFlag flag;
	
	if (g_GroupPass == GroupPass_First)
	{
		if (g_GroupState == GroupState_InGroup)
		{
			if (StrEqual(key, "flags", false))
			{
				int len = strlen(value);
				for (int i = 0; i < len; i++)
				{
					if (!FindFlagByChar(value[i], flag))
					{
						continue;
					}

				#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR <= 7
					SetAdmGroupAddFlag(g_CurGrp, flag, true);
				#else
					g_CurGrp.SetFlag(flag, true);
				#endif
				}
			} 
			
			else if (StrEqual(key, "immunity", false)) 
				g_NeedReparse = true;
		} 
		
		else if (g_GroupState == GroupState_Overrides)
		{
			OverrideRule rule = StrEqual(value, "allow", false) ? Command_Allow : Command_Deny;

			if (key[0] == '@')
			{
			#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR <= 7
				AddAdmGroupCmdOverride(g_CurGrp, key[1], Override_CommandGroup, rule);
			#else
				g_CurGrp.AddCommandOverride(key[1], Override_CommandGroup, rule);
			#endif
			}
				
			else
			{
			#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR <= 7
				AddAdmGroupCmdOverride(g_CurGrp, key, Override_Command, rule);
			#else
				g_CurGrp.AddCommandOverride(key, Override_Command, rule);
			#endif
			}
		}
	} 
	
	else if (g_GroupPass == GroupPass_Second && g_GroupState == GroupState_InGroup) 
	{
		/* Check for immunity again, core should handle double inserts */
		if (StrEqual(key, "immunity", false))
		{
			/* If it's a value we know about, use it */
			if (StrEqual(value, "*"))
			{
			#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR <= 7
				SetAdmGroupImmunityLevel(g_CurGrp, 2);
			#else
				g_CurGrp.ImmunityLevel = 2;
			#endif
			}
				
			else if (StrEqual(value, "$")) 
			{
			#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR <= 7
				SetAdmGroupImmunityLevel(g_CurGrp, 1);
			#else	
				g_CurGrp.ImmunityLevel = 1;
			#endif
			}
				
			else 
			{
				int level;
				if (StringToIntEx(value, level))
				{
				#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR <= 7
					SetAdmGroupImmunityLevel(g_CurGrp, level);
				#else
					g_CurGrp.ImmunityLevel = level;
				#endif
				}
					
				else 
				{
					GroupId id = value[0] == '@' ? FindAdmGroup(value[1]) : FindAdmGroup(value);
					if (id != INVALID_GROUP_ID)
					{
					#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR <= 7
						SetAdmGroupImmuneFrom(g_CurGrp, id);
					#else
						g_CurGrp.AddGroupImmunity(id);
					#endif
					}
					else 
						ParseError("Unable to find group: \"%s\"", value);
				}
			}
		}
	}
	
	return SMCParse_Continue;
}

public SMCResult ReadGroups_EndSection(SMCParser smc)
{
	/* If we're ignoring, skip out */
	if (g_IgnoreLevel)
	{
		g_IgnoreLevel--;
		return SMCParse_Continue;
	}
	
	if (g_GroupState == GroupState_Overrides)
		g_GroupState = GroupState_InGroup;
		
	else if (g_GroupState == GroupState_InGroup)
	{
		g_GroupState = GroupState_Groups;
		g_CurGrp = INVALID_GROUP_ID;
	}
	
	else if (g_GroupState == GroupState_Groups) 
		g_GroupState = GroupState_None;
	
	return SMCParse_Continue;
}

public SMCResult ReadGroups_CurrentLine(SMCParser smc, const char[] line, int lineno)
{
	g_CurrentLine = lineno;
	
	return SMCParse_Continue;
}

static void InitializeGroupParser()
{
	if (!g_hGroupParser)
	{
		g_hGroupParser = new SMCParser();
		g_hGroupParser.OnEnterSection = ReadGroups_NewSection;
		g_hGroupParser.OnKeyValue = ReadGroups_KeyValue;
		g_hGroupParser.OnLeaveSection = ReadGroups_EndSection;
		g_hGroupParser.OnRawLine = ReadGroups_CurrentLine;
	}
}

static void InternalReadGroups(const char[] path, GroupPass pass)
{
	/* Set states */
	InitGlobalStates();
	g_GroupState = GroupState_None;
	g_CurGrp = INVALID_GROUP_ID;
	g_GroupPass = pass;
	g_NeedReparse = false;
	
	SMCError err = g_hGroupParser.ParseFile(path);
	if (err != SMCError_Okay)
	{
		char buffer[64];
		//bool bufferError = g_hGroupParser.GetErrorString(err, buffer, sizeof(buffer));
		ParseError("%s", g_hGroupParser.GetErrorString(err, buffer, sizeof(buffer)) ? buffer : "Fatal parse error" );
	}
}

void ReadGroups()
{
	InitializeGroupParser();
	
	BuildPath(Path_SM, g_Filename, sizeof(g_Filename), "configs/sourcebans/sb_admin_groups.cfg");
	
	InternalReadGroups(g_Filename, GroupPass_First);
	
	if (g_NeedReparse)
		InternalReadGroups(g_Filename, GroupPass_Second);
}