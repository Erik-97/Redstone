/*
This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/

/* Auto-Updater Support */
#define UPDATE_URL  "https://github.com/stickz/Redstone/raw/build/updater/nd_commander_chair/nd_commander_chair.txt"
#include "updater/standard.sp"

#include <sourcemod>
#include <autoexecconfig>
#include <sdktools>
#include <nd_stocks>
#include <nd_com_eng>
#include <nd_redstone>
#include <nd_rounds>
#include <nd_print>
#include <nd_resources>
#include <nd_resource_eng>
#include <nd_entities>

public Plugin myinfo =
{
	name = "[ND] Commander Chair",
	author = "Stickz",
	description = "Blocks entering chair until both team gets a commander",
	version = "dummy",
	url = "https://github.com/stickz/Redstone/"
}

ConVar cvarMinEach;
ConVar cvarMinTeam;
ConVar cvarMinTotal;
ConVar cvarMaxRStart;
ConVar cvarMaxPromote;
ConVar cvarSelectMin;
ConVar cvarSelectMax;
ConVar cvarSecCount;

bool ChairWaitRStartElapsed = false;
bool ChairWaitPromoteElapsed[2] = { false, ...};

Handle BunkerDelayTimer = INVALID_HANDLE;
Handle PromoteDelayTimer[2] = { INVALID_HANDLE, ...};

public void OnPluginStart()
{
	CreatePluginConvars(); // for convars	

	LoadTranslations("nd_common.phrases");
	LoadTranslations("nd_commander_chair.phrases");
	
	AddUpdaterLibrary(); //auto-updater
	
	HookEvent("resource_captured", Event_ResourceCaptured, EventHookMode_Post);
	
	// If the plugin loads late, disable the chair waiting
	bool rStart = ND_RoundStarted();	
	ToggleWaitPromote(rStart);
	ChairWaitRStartElapsed = rStart;
}

public void ND_OnPreRoundStart()
{
	// If we have enough players, set commander selection time to min; otherwise, set it to max.
	int selectTime = RStartThresholdReached() ? cvarSelectMin.IntValue : cvarSelectMax.IntValue;
	ServerCommand("sm_cvar nd_commander_election_time %d", selectTime);
}

public void ND_OnRoundStarted() 
{
	ToggleWaitPromote(false);
	ChairWaitRStartElapsed = false;
	BunkerDelayTimer = CreateTimer(cvarMaxRStart.FloatValue, TIMER_EnterChairRStartDelay, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void ND_OnRoundEnded() 
{
	if (BunkerDelayTimer != INVALID_HANDLE && IsValidHandle(BunkerDelayTimer))
	{
		CloseHandle(BunkerDelayTimer);
		BunkerDelayTimer = INVALID_HANDLE;
	}
	
	for (int h = 0; h < 2; h++) {
		if (PromoteDelayTimer[h] != INVALID_HANDLE && IsValidHandle(PromoteDelayTimer[h])) 
		{
			CloseHandle(PromoteDelayTimer[h]);
			PromoteDelayTimer[h] = INVALID_HANDLE;
		}
	}
}

public void ND_OnCommanderPromoted(int client, int team)
{
	PromoteDelayTimer[team-2] = CreateTimer(cvarMaxRStart.FloatValue, TIMER_EnterChairPromoteDelay, 
						GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void ND_BothCommandersPromoted(int consort, int empire)
{
	// Show early chair unlock message
	if (!ChairWaitRStartElapsed)
		NotifyCommandersOfChairUnlock("Chair Unlocked");
}

public Action Event_ResourceCaptured(Event event, const char[] name, bool dontBroadcast)
{
	// Check if the team that captured the point is valid
	int team = event.GetInt("team");
	if (team != TEAM_EMPIRE && team != TEAM_CONSORT) 
		return Plugin_Continue;
	
	// Check if the other team's promote delay has elapsed yet or if both teams had a commander
	int otherTeam = getOtherTeam(team);
	if (ChairWaitPromoteElapsed[otherTeam-2] || BothTeamsHadCommander())
		return Plugin_Continue;	
	
	// Check if the round is started the resource points are availible
	if (!ND_RoundStarted() || !ND_ResPointsCached())
		return Plugin_Continue;
	
	int type = event.GetInt("type");
	
	if (type == RESOURCE_PRIME)
	{		
		if (TeamOwnsEnoughSecondaries(team))
		{			
			DoTeamChairUnlock(otherTeam);
		}
	}
	
	else if (type == RESOURCE_SECONDARY)
	{
		if (TeamOwnsEnoughSecondaries(team) && ND_GetPrimeOwner() == team)
		{
			DoTeamChairUnlock(otherTeam);
		}
	}
	
	return Plugin_Continue;
}

void DoTeamChairUnlock(int otherTeam)
{
	ChairWaitPromoteElapsed[otherTeam-2] = true;
	NotifyCommandersOfChairUnlock("May Enter Chair");
}

bool TeamOwnsEnoughSecondaries(int team)
{
	int count = 0;
	
	int secCount = ND_GetSecondaryCount();
	for (int sec = 0; sec < secCount; secCount++)
	{
		int entity = ND_GetSecondaryEnt(sec);
		int owner = ND_GetResourceOwner(entity);
		
		if (owner == team)
			count++;
	}	
	
	return count >= cvarSecCount.IntValue;
}

public Action TIMER_EnterChairRStartDelay(Handle timer)
{
	ChairWaitRStartElapsed = true;
	
	// Show chair lock expire message, if commanders aren't selected in-time
	if (!BothTeamsHadCommander())
		NotifyCommandersOfChairUnlock("May Enter Chair");
		
	return Plugin_Continue;
}

public Action TIMER_EnterChairPromoteDelay(Handle timer, any:userid)
{
	// Get client and check if userid is valid
	int client = GetClientOfUserId(userid);		
	if (client == INVALID_USERID)
		return Plugin_Handled;
	
	// Get the client team and check if valid
	int team = GetClientTeam(client);
	if (team <= 1)
		return Plugin_Handled;
	
	// If the chair wait has already elapsed, exit
	if (ChairWaitPromoteElapsed[team-2])
		return Plugin_Handled;
	
	// Set the promote wait elapsed to true
	ChairWaitPromoteElapsed[team-2] = true;
	
	// Show chair lock expire message, if commanders aren't selected in-time
	if (!BothTeamsHadCommander() && ChairWaitRStartElapsed)
		PrintMessage(client, "May Enter Chair");
		
	return Plugin_Continue;
}

public Action ND_OnCommanderEnterChair(int client, int team)
{	
	if (!BothTeamsHadCommander())
	{
		// Check if both the wait after round start and the wait after one commander is promoted is active
		bool rStartWait = !ChairWaitRStartElapsed && RStartThresholdReached();
		bool promoteWait = !ChairWaitPromoteElapsed[team-2] && WaitPromotionThresholdReached();
		
		if (rStartWait && promoteWait)
		{
			PrintMessageTI1(client, "Wait Enter Chair", cvarMaxPromote.IntValue);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

bool TotalPlayerTresholdReached() {
	return ND_GetClientCount() >= cvarMinTotal.IntValue;
}

bool RStartThresholdReached()
{
	bool teamThreshold = RED_OnTeamCount() >= cvarMinTeam.IntValue;
	return teamThreshold || TotalPlayerTresholdReached();
}

bool WaitPromotionThresholdReached()
{
	int min = cvarMinEach.IntValue;
	int empire = RED_GetTeamCount(TEAM_EMPIRE);
	int consort = RED_GetTeamCount(TEAM_CONSORT);
	bool teamThreshold = empire >= min && consort >= min;
	return teamThreshold || TotalPlayerTresholdReached();
}

bool BothTeamsHadCommander() {
	return ND_InitialCommandersReady(true) || ND_GetCommanderCount() >= 2;
}

void ToggleWaitPromote(bool value)
{
	ChairWaitPromoteElapsed[0] = value;
	ChairWaitPromoteElapsed[1] = value;
}

void NotifyCommandersOfChairUnlock(const char[] phrase)
{
	// Print phrase to empire & consort commanders, if availible
	PrintMessageCom(ND_GetCommanderOnTeam(TEAM_EMPIRE), phrase);
	PrintMessageCom(ND_GetCommanderOnTeam(TEAM_CONSORT), phrase);
}

void CreatePluginConvars()
{
	AutoExecConfig_Setup("nd_commander_chair");
	
	cvarMinEach		=	AutoExecConfig_CreateConVar("sm_chair_wait_each", "3", "Min number of players on each team to block chair after promotion");
	cvarMinTeam		=	AutoExecConfig_CreateConVar("sm_chair_block_team", "8", "Min number of players on any team required to block char after round start");
	cvarMinTotal		=	AutoExecConfig_CreateConVar("sm_chair_block_total", "12", "Min number of total players required to block the command chair");
	cvarMaxRStart		= 	AutoExecConfig_CreateConVar("sm_chair_max_rstart", "120", "How long to block chair after round start if nobody applies for commander?");
	cvarMaxPromote		= 	AutoExecConfig_CreateConVar("sm_chair_max_promote", "60", "How long to block chair after promotion if nobody applies for commander?");	
	cvarSelectMin		=	AutoExecConfig_CreateConVar("sm_chair_select_min", "15", "Duration to wait to select commanders, with chair blocking");
	cvarSelectMax		=	AutoExecConfig_CreateConVar("sm_chair_select_max", "30", "Duration to wait to select commanders, without chair blocks");
	cvarSecCount		=	AutoExecConfig_CreateConVar("sm_chair_sec_unlock", "2", "How many secondaries a team must own to unlock the chair");
	
	AutoExecConfig_EC_File();
}
