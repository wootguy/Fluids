dictionary g_player_states;

CCVar@ cvar_pp_cooldown;

class PlayerState {
	bool autoPee = false;
	bool male = true;
	bool isTesting = false;
	int bone = -1;
	float offset = 0;
	float lastPee = 0;
	float nextPee = 0;
}

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "github" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	
	@cvar_pp_cooldown = CCVar("cooldown", 60, "pee cooldown", ConCommandFlag::AdminOnly);
	
	g_Scheduler.SetInterval("auto_pee", 1.0f, -1);
}

void MapInit()
{
	g_Game.PrecacheModel("sprites/pee.spr");
}

void MapActivate() {	
	array<string>@ stateKeys = g_player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
		state.lastPee = -999;
	}
}

void auto_pee() {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
		if (p is null or !p.IsConnected() or !p.IsAlive())
			continue;
		
		
		PlayerState@ state = getPlayerState(p);
		if (state.autoPee && state.nextPee < g_Engine.time) {
			state.nextPee = getNextAutoPee();
			state.lastPee = g_Engine.time;
			peepee(EHandle(p), 1.0f, 4, false);
		}
	}
}

// Will create a new state if the requested one does not exit
PlayerState@ getPlayerState(CBasePlayer@ plr)
{
	if (plr is null or !plr.IsConnected())
		return null;
		
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN' or steamId == 'BOT') {
		steamId = plr.pev.netname;
	}
	
	if ( !g_player_states.exists(steamId) )
	{
		PlayerState state;
		g_player_states[steamId] = state;
	}
	return cast<PlayerState@>( g_player_states[steamId] );
}

int bone = 35;
//int bone = 36;

void peepee(EHandle h_plr, float strength, int squirts_left, bool isTest) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	
	if (plr is null or strength <= 0 or !plr.IsAlive()) {
		return;
	}
	
	PlayerState@ state = getPlayerState(plr);
	
	if (isTest && (strength <= 0.5f || !state.isTesting)) {
		state.isTesting = false;
		g_PlayerFuncs.SayText(plr, 'Test pee disabled.\n');
		return;
	}
	
	Vector pos, angles;	
	pos = plr.pev.origin;
	
	if (state.bone != -1) {
		plr.GetBonePosition(bone, pos, angles);
	} else {
		float offset = state.offset;
		if (plr.pev.flags & FL_DUCKING != 0) {
			offset *= 0.5f;
		}
		pos.z += offset;
	}
	
	angles = plr.pev.v_angle;
	//angles.x *= 0.8f;
	//angles.x = 0;
	angles.x -= 10;
	if (angles.x < 0) {
		angles.x = Math.max(angles.x * 2, -75);
	}
	
	Math.MakeVectors(angles);
	
	Vector dir = g_Engine.v_forward;
	
	float speed = strength > 0.5f ? 1.0f : strength / 0.5f;
	int count = strength > 0.5f ? 2 : 1;
	//println("PEE " + strength);
	
	//int speed = int(16*strength + plr.pev.velocity.Length()*0.1f);
	//te_spritetrail(pos, pos + dir, "sprites/pitdronespit.spr", 4, 4, 2, speed, 2);
	//te_blood(pos, Vector(0,0,-1), 192, 2);
	//te_bloodstream(pos, dir, 192, speed);
	//te_spray(plr.pev.origin, g_Engine.v_forward, "sprites/pee.spr", 2, 127, 32, 0);
	
	NetworkMessageDest msgType = isTest ? MSG_ONE_UNRELIABLE : MSG_BROADCAST;
	edict_t@ dest = isTest ? @plr.edict() : null;
	
	if (plr.pev.waterlevel >= WATERLEVEL_WAIST) {
		te_firefield(plr.pev.origin, 16, "sprites/pee.spr", count, 8, 255, msgType, dest);
	} else {
		Vector peedir = state.male ? dir*50 + (dir*150*speed) : Vector(0,0,0);
		
		count = isTest ? 1 : count;
		int life = isTest ? 0 : 255;
		int flags = isTest ? 0 : 4;		
		
		te_breakmodel(pos, Vector(0,0,0), peedir + plr.pev.velocity, 1, "sprites/pee.spr", count, life, flags, msgType, dest);
	}
	
	float delay = isTest ? 0.1f : 0.05f;
	if (strength < 0.1f && Math.RandomLong(0,2) == 0 && squirts_left > 0) {
		delay += Math.RandomFloat(0.3, 0.7);
		squirts_left--;
	}
	
	g_Scheduler.SetTimeout("peepee", delay, h_plr, strength - 0.01f, squirts_left, isTest);
}

string format_float(float f)
{
	uint decimal = uint(((f - int(f)) * 10)) % 10;
	return "" + int(f) + "." + decimal;
}

float getNextAutoPee() {
	return g_Engine.time + cvar_pp_cooldown.GetInt();
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args, bool isConsoleCommand)
{	
	PlayerState@ state = getPlayerState(plr);
	
	if ( args.ArgC() > 0 )
	{
		if ( args[0] == ".pp" )
		{
			if (args.ArgC() > 1) {
				if (args[1] == 'auto') {
					state.autoPee = !state.autoPee;
					state.nextPee = getNextAutoPee();
					g_PlayerFuncs.SayText(plr, 'Auto pee ' + (state.autoPee ? "enabled" : "disabled") + '.\n');
					return true;
				}
				if (args[1] == 'test') {
					state.isTesting = !state.isTesting;
					if (state.isTesting) {
						g_PlayerFuncs.SayText(plr, 'Test pee enabled\n');
						peepee(EHandle(plr), 5.0f, 4, true);
					}
					
					return true;
				}
				if (args[1] == 'm') {
					g_PlayerFuncs.SayText(plr, 'Pee mode is MALE.\n');
					state.male = true;
					return true;
				}
				if (args[1] == 'f') {
					g_PlayerFuncs.SayText(plr, 'Pee mode is FEMALE.\n');
					state.male = false;
					return true;
				}
				if (args[1] == 'offset') {
					if (args.ArgC() > 2) {
						float offset = atof(args[2]);
						if (offset < -36) {
							offset = -36;
						} else if (offset > 36) {
							offset = 36;
						}
						
						g_PlayerFuncs.SayText(plr, 'Pee offset set to ' + offset + '.\n');
						state.offset = offset;
						state.bone = -1;
						return true;
					}
				}
				if (args[1] == 'bone') {
					if (args.ArgC() > 2) {
						int bone = atoi(args[2]);
						if (bone < 0) {
							bone = -1;
						} else if (bone > 255) {
							bone = 255;
						}
						
						g_PlayerFuncs.SayText(plr, 'Pee bone set to ' + bone + '.\n');
						state.bone = bone;
						return true;
					}
				}
			}
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '-----------------------------Pee Pee Poo Poo Commands-----------------------------\n\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".pee" to pee.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".pp auto" to toggle automatic peeing.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".pp [m/f]" to change pee mode.\n');
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nAdvanced usage:\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".pp offset [-36 to +36]" to set a vertical pee offset\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        - good enough if you\'re not using emotes\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        - disables bone peeing\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".pp bone [0-255]" to set a model bone to pee from\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        - for accurate peeing when using emotes\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        - displays incorrectly in the first-person view\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        - doesn\'t work for all models.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '        - most models only have 40 bones\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    Type ".pp test" to test pee stream (only you can see it)\n');
			
			
			float delta = g_Engine.time - state.lastPee;
			string status = "";
			if (delta < cvar_pp_cooldown.GetInt()) {
				status = "\nYou can pee in " + int((cvar_pp_cooldown.GetInt() - delta) + 0.99f) + " seconds.\n";
			}
			else {
				status = "\nYou can pee now.\n";
			}
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, status);
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\n-----------------------------------------------------------------------------------\n');
		
			if (!isConsoleCommand) {
				g_PlayerFuncs.SayText(plr, 'Say ".pee" to pee.\n');
				g_PlayerFuncs.SayText(plr, 'Type ".pp" in console for more commands/info\n');
			}
			return true;
		}
		
		if ( args[0] == ".pee" )
		{
			float delta = g_Engine.time - state.lastPee;
			if (delta < cvar_pp_cooldown.GetInt()) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCENTER, "Wait " + int((cvar_pp_cooldown.GetInt() - delta) + 0.99f) + " seconds\n");
				return true;
			}
			state.nextPee = getNextAutoPee();
			state.lastPee = g_Engine.time;
			peepee(EHandle(plr), 1.0f, 4, false);
			return true;
		}
	}
	return false;
}

HookReturnCode ClientSay( SayParameters@ pParams )
{	
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	
	if (doCommand(plr, args, false))
	{
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	
	return HOOK_CONTINUE;
}

CClientCommand _pp("pp", "Pee pee poo poo commands", @consoleCmd );
CClientCommand _pee("pee", "Pee pee poo poo commands", @consoleCmd );

void consoleCmd( const CCommand@ args )
{
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}

void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

void te_spray(Vector pos, Vector dir, string sprite="sprites/bubble.spr", 
	uint8 count=8, uint8 speed=127, uint8 noise=255, uint8 rendermode=0,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_SPRAY);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteCoord(dir.x);
	m.WriteCoord(dir.y);
	m.WriteCoord(dir.z);
	m.WriteShort(g_EngineFuncs.ModelIndex(sprite));
	m.WriteByte(count);
	m.WriteByte(speed);
	m.WriteByte(noise);
	m.WriteByte(rendermode);
	m.End();
}


void te_spritetrail(Vector start, Vector end, 
	string sprite="sprites/hotglow.spr", uint8 count=2, uint8 life=0, 
	uint8 scale=1, uint8 speed=16, uint8 speedNoise=8,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_SPRITETRAIL);
	m.WriteCoord(start.x);
	m.WriteCoord(start.y);
	m.WriteCoord(start.z);
	m.WriteCoord(end.x);
	m.WriteCoord(end.y);
	m.WriteCoord(end.z);
	m.WriteShort(g_EngineFuncs.ModelIndex(sprite));
	m.WriteByte(count);
	m.WriteByte(life);
	m.WriteByte(scale);
	m.WriteByte(speedNoise);
	m.WriteByte(speed);
	m.End();
}

void te_blood(Vector pos, Vector dir, uint8 color=70, uint8 speed=16,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_BLOOD);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteCoord(dir.x);
	m.WriteCoord(dir.y);
	m.WriteCoord(dir.z);
	m.WriteByte(color);
	m.WriteByte(speed);
	m.End();
}

void te_bloodstream(Vector pos, Vector dir, uint8 color=70, uint8 speed=64,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_BLOODSTREAM);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteCoord(dir.x);
	m.WriteCoord(dir.y);
	m.WriteCoord(dir.z);
	m.WriteByte(color);
	m.WriteByte(speed);
	m.End();
}

void te_breakmodel(Vector pos, Vector size, Vector velocity, 
	uint8 speedNoise=16, string model="models/hgibs.mdl", 
	uint8 count=8, uint8 life=0, uint8 flags=20,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_BREAKMODEL);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteCoord(size.x);
	m.WriteCoord(size.y);
	m.WriteCoord(size.z);
	m.WriteCoord(velocity.x);
	m.WriteCoord(velocity.y);
	m.WriteCoord(velocity.z);
	m.WriteByte(speedNoise);
	m.WriteShort(g_EngineFuncs.ModelIndex(model));
	m.WriteByte(count);
	m.WriteByte(life);
	m.WriteByte(flags);
	m.End();
}


void te_firefield(Vector pos, uint16 radius=128, 
	string sprite="sprites/grenade.spr", uint8 count=128, 
	uint8 flags=30, uint8 life=5,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) 
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_FIREFIELD);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteShort(radius);
	m.WriteShort(g_EngineFuncs.ModelIndex(sprite));
	m.WriteByte(count);
	m.WriteByte(flags);
	m.WriteByte(life);
	m.End();
}