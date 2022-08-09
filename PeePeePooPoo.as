dictionary g_player_states;

CCVar@ cvar_pp_cooldown;
CCVar@ cvar_bleed_cooldown;

string pee_sprite = "sprites/pee.spr";
string coom_sprite = "sprites/coom.spr";
string bleed_sprite = "sprites/bleed.spr";
string milk_sound = "twlz/kimochi.wav";
string splat_sound = "pp/splat.wav";

array<string> coom_sounds = {"pp/coom.wav", "pp/coom2.wav", "pp/coom3.wav"};

float BLEED_DELAY = 1;
float BLEED_LIFE = 10; // max life before killing blood entity

class PlayerState {
	bool autoBleed = false;
	bool realBleed = false;
	bool autoPee = false;
	bool male = true;
	bool isTesting = false;
	int bone = -1;
	float offset = 0;
	float lastPee = -999;
	float nextPee = 0;
	float lastBleed = -999;
}

class BloodChunk : ScriptBaseAnimating
{
	float thinkDelay = 0.1;
	float spawnTime = 0;
	
	array<string> big_blood_decals = {"{blood4", "{blood5", "{blood6"};
	
	void Spawn()
	{		
		self.pev.movetype = MOVETYPE_TOSS;
		self.pev.solid = SOLID_BBOX;
		
		g_EntityFuncs.SetModel( self, pev.model );
		
		g_EntityFuncs.SetSize(pev, Vector(0,0,0), Vector(0,0,0));
		
		pev.frame = 0;
		pev.scale = 0.8f;
		pev.rendercolor = Vector(64, 0, 0);
		//self.ResetSequenceInfo();
		
		SetThink( ThinkFunction( MoveThink ) );
		self.pev.nextthink = g_Engine.time + thinkDelay;
		
		spawnTime = g_Engine.time;
	}
	
	void MoveThink()
	{
		float nextThink = g_Engine.time + thinkDelay;
		
		pev.frame += 1;
		if (pev.frame > 8) {
			pev.frame = 0;
		}
		
		if (g_EngineFuncs.PointContents(pev.origin) == CONTENTS_WATER) {
			Vector splatOri = pev.origin;
			splatOri.z = g_Utility.WaterLevel(pev.origin, pev.origin.z, pev.origin.z + 256) - 16;
			te_firefield(splatOri, 6, bleed_sprite, 16, 8, 50);
			g_EntityFuncs.Remove(self);
		}
		
		if (g_Engine.time - spawnTime > BLEED_LIFE) {
			g_EntityFuncs.Remove(self);
		}
		
		self.pev.nextthink = nextThink;
	}
	
	void Touch( CBaseEntity@ pOther )
	{
		uint8 splatScale = 5;
		float speed = pev.velocity.Length();
		
		if (pOther.IsBSPModel()) {
			string decal = "{blood8";
			
			if (speed > 500) {
				decal = big_blood_decals[Math.RandomLong(0, big_blood_decals.size()-1)];
				splatScale = 10;
			} else if (speed > 300) {
				decal = "{blood7";
				splatScale = 7;
			}
			
			te_decal(pev.origin, pOther, decal);
		}
		
		te_bloodsprite(pev.origin, "sprites/bloodspray.spr", "sprites/blood.spr", 70, splatScale);
		
		float vol = Math.min(1.0f, 0.15f + (speed / 10000.0f));
		int pit = Math.RandomLong(90, 110);
		g_SoundSystem.PlaySound(self.edict(), CHAN_VOICE, splat_sound, vol, 1.0f, 0, pit, 0, true, pev.origin);
		g_EntityFuncs.Remove(self);
	}
}

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "github" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	
	@cvar_pp_cooldown = CCVar("cooldown", 60, "pee cooldown", ConCommandFlag::AdminOnly);
	@cvar_bleed_cooldown = CCVar("bloodcooldown", 1, "bleed cooldown", ConCommandFlag::AdminOnly);
	
	g_Scheduler.SetInterval("auto_pee", 1.0f, -1);
}

void MapInit()
{
	g_Game.PrecacheModel(pee_sprite);
	g_Game.PrecacheModel(coom_sprite);
	g_Game.PrecacheModel(bleed_sprite);
	
	for (uint i = 0; i < coom_sounds.size(); i++) {
		g_SoundSystem.PrecacheSound(coom_sounds[i]);
		g_Game.PrecacheGeneric("sound/" + coom_sounds[i]);
	}
	
	g_SoundSystem.PrecacheSound(milk_sound);
	g_Game.PrecacheGeneric("sound/" + milk_sound);
	
	g_SoundSystem.PrecacheSound(splat_sound);
	g_Game.PrecacheGeneric("sound/" + splat_sound);
}

void MapActivate() {	
	array<string>@ stateKeys = g_player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( g_player_states[stateKeys[i]] );
		state.lastPee = -999;
		state.lastBleed = -999;
	}
	
	g_CustomEntityFuncs.RegisterCustomEntity( "BloodChunk", "BloodChunk" );
}

void bleed(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	state.lastBleed = g_Engine.time;
	
	if (plr.pev.waterlevel >= WATERLEVEL_WAIST) {
		te_firefield(plr.pev.origin, 6, bleed_sprite, 16, 8, 50);
		return;
	}
	
	float x = 3;
	Vector bloodOri = plr.pev.origin + Vector(Math.RandomFloat(-x, x), Math.RandomFloat(-x, x), Math.RandomFloat(-x, x));
	
	float offset = state.offset;
	if (plr.pev.flags & FL_DUCKING != 0) {
		offset *= 0.5f;
	}
	
	bloodOri.z += offset;
	
	dictionary keys;
	keys["origin"] = bloodOri.ToString();
	keys["velocity"] = plr.pev.velocity.ToString();
	keys["model"] = "sprites/blood.spr";
	CBaseEntity@ blood = g_EntityFuncs.CreateEntity("BloodChunk", keys, true);
	blood.pev.velocity = plr.pev.velocity;
	@blood.pev.owner = @plr.edict();
	g_EntityFuncs.SetSize(blood.pev, Vector(0,0,0), Vector(0,0,0));
}

void auto_pee() {
	for ( int i = 1; i <= g_Engine.maxClients; i++ )
	{
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		if (plr is null or !plr.IsConnected() or !plr.IsAlive())
			continue;
		
		
		PlayerState@ state = getPlayerState(plr);
		if (state.autoPee && state.nextPee < g_Engine.time) {
			state.nextPee = getNextAutoPee();
			state.lastPee = g_Engine.time;
			peepee(EHandle(plr), 1.0f, 4, false, false);
		}
		
		if ((state.autoBleed or state.realBleed) and g_Engine.time - state.lastBleed > cvar_bleed_cooldown.GetFloat()) {
			if (state.autoBleed or plr.pev.health < plr.pev.max_health) {
				bleed(plr);
			}
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

void peepee(EHandle h_plr, float strength, int squirts_left, bool isTest, bool isBlood) {
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
		plr.GetBonePosition(state.bone, pos, angles);
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
		string model = isBlood ? bleed_sprite : pee_sprite;
		te_firefield(plr.pev.origin, 16, model, count, 8, 255, msgType, dest);
	} else {
		Vector peedir = state.male ? dir*50 + (dir*150*speed) : Vector(0,0,0);
		
		count = isTest ? 1 : count;
		int life = isTest ? 0 : 255;
		int flags = isTest ? 0 : 4;		
		
		string model = isBlood ? bleed_sprite : pee_sprite;
		te_breakmodel(pos, Vector(0,0,0), peedir + plr.pev.velocity, 1, model, count, life, flags, msgType, dest);
	}
	
	float delay = isTest ? 0.1f : 0.05f;
	if (strength < 0.1f && Math.RandomLong(0,2) == 0 && squirts_left > 0) {
		delay += Math.RandomFloat(0.3, 0.7);
		squirts_left--;
	}
	
	g_Scheduler.SetTimeout("peepee", delay, h_plr, strength - 0.01f, squirts_left, isTest, isBlood);
}

void delay_decal(Vector pos, EHandle h_hitEnt, string decal) {
	te_decal(pos, h_hitEnt, decal);
}

void coom(EHandle h_plr, float strength, int squirts_left, bool isBlood) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	
	if (plr is null or strength <= 0 or !plr.IsAlive()) {
		return;
	}
	
	PlayerState@ state = getPlayerState(plr);
	
	Vector pos, angles;	
	pos = plr.pev.origin;
	
	if (state.bone != -1) {
		plr.GetBonePosition(state.bone, pos, angles);
	} else {
		
		float offset = state.offset;
		if (plr.pev.flags & FL_DUCKING != 0) {
			offset *= 0.5f;
		}
		pos.z += offset;
	}

	angles = plr.pev.v_angle;
	Math.MakeVectors(angles);
	Vector lookdir = g_Engine.v_forward;

	angles.x -= 15;
	
	Math.MakeVectors(angles);
	Vector coomdir = g_Engine.v_forward;
	
	
	
	float speed = strength;
	int count = strength > 0.5f ? 2 : 1;
	
	if (plr.pev.waterlevel >= WATERLEVEL_WAIST) {
		string spr = isBlood ? bleed_sprite : coom_sprite;
		te_firefield(plr.pev.origin, 6, spr, 16, 8, 255, MSG_BROADCAST, null);
	} else {
		Vector peedir = state.male ? coomdir : Vector(0,0,0);
		
		int life = 255;
		int flags = 4;
		int color = isBlood ? 70 : 5;
		te_bloodstream(pos, coomdir, color, int(speed*200));
		
		if (strength == 1.0f) {
			float coomDist = strength*256;
			Vector headPos = plr.pev.origin + plr.pev.view_ofs;
			TraceResult tr;
			g_Utility.TraceLine(headPos, headPos + lookdir*coomDist, ignore_monsters, plr.edict(), tr );
			
			if (tr.flFraction < 1.0f) {
				float impactTime = (tr.vecEndPos - pos).Length() / coomDist;
				string decal = isBlood ? "{bigblood1" : "{mommablob";
				g_Scheduler.SetTimeout("delay_decal", impactTime, tr.vecEndPos, EHandle(g_EntityFuncs.Instance(tr.pHit)), decal);
			}
		}
		
	}
	
	float delay = 1.0f;
	if (--squirts_left > 0) {
		g_Scheduler.SetTimeout("coom", delay, h_plr, strength * 0.6f, squirts_left, isBlood);
	}
	
}

void lactate(EHandle h_plr, float strength, int squirts_left, bool isBlood) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	
	if (plr is null or strength <= 0 or !plr.IsAlive()) {
		return;
	}
	
	PlayerState@ state = getPlayerState(plr);
	
	Vector pos, angles;	
	pos = plr.pev.origin;
	
	if (state.bone != -1) {
		plr.GetBonePosition(state.bone, pos, angles);
	} else {
		
		float offset = state.offset;
		if (plr.pev.flags & FL_DUCKING != 0) {
			offset *= 0.5f;
		}
		pos.z += offset;
	}

	angles = plr.pev.v_angle;
	angles.x *= 0.5f;
	Math.MakeVectors(angles);
	Vector lookdir = g_Engine.v_forward;
	
	pos.z += 8;
	pos = pos + lookdir*8;
	Vector latDir = g_Engine.v_right;
	float nipSpacing = 4;
	
	Vector angles1 = angles;
	angles1.x += Math.RandomFloat(0, -40);
	angles1.y += Math.RandomFloat(0, -40);
	Math.MakeVectors(angles1);
	Vector dir1 = g_Engine.v_forward;
	
	Vector angles2 = angles;
	angles2.x += Math.RandomFloat(0, -40);
	angles2.z += Math.RandomFloat(0, 40);
	Math.MakeVectors(angles2);
	Vector dir2 = g_Engine.v_forward;
	
	float speed = strength;
	int count = strength > 0.5f ? 2 : 1;
	
	Vector pos1 = pos + latDir*nipSpacing;
	Vector pos2 = pos - latDir*nipSpacing;
	
	if (plr.pev.waterlevel >= WATERLEVEL_WAIST) {
		string model = isBlood ? bleed_sprite : coom_sprite;
		te_firefield(pos1, 6, model, 16, 8, 255, MSG_BROADCAST, null);
		te_firefield(pos2, 6, model, 16, 8, 255, MSG_BROADCAST, null);
	} else {
		int color = isBlood ? 70 : 5;
		int color2 = isBlood ? 70 : 10;
		
		te_bloodstream(pos1, dir1, color, int(speed*200));
		te_bloodstream(pos2, dir2, color, int(speed*200));
		
		te_bloodsprite(pos1, "sprites/bloodspray.spr", "sprites/blood.spr", color2, 3);
		te_bloodsprite(pos2, "sprites/bloodspray.spr", "sprites/blood.spr", color2, 3);
	}
	
	float delay = 1.0f;
	if (--squirts_left > 0) {
		g_Scheduler.SetTimeout("lactate", delay, h_plr, strength * 0.6f, squirts_left, isBlood);
	}
}

void te_bloodsprite(Vector pos, string sprite1="sprites/bloodspray.spr",
	string sprite2="sprites/blood.spr", uint8 color=70, uint8 scale=3,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_BLOODSPRITE);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteShort(g_EngineFuncs.ModelIndex(sprite1));
	m.WriteShort(g_EngineFuncs.ModelIndex(sprite2));
	m.WriteByte(color);
	m.WriteByte(scale);
	m.End();
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
						peepee(EHandle(plr), 5.0f, 4, true, false);
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
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".coom" to coom.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".milk" to lactate.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".blood" to bleed once.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".bleed" to bleed constantly.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".bleedhp" to bleed only when health is not maxed.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".bloodpee" to pee blood.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".bloodcoom" to coom blood.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Type ".bloodmilk" to lactate blood.\n');
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
				g_PlayerFuncs.SayText(plr, 'Say ".coom" to coom.\n');
				g_PlayerFuncs.SayText(plr, 'Say ".milk" to lactate.\n');
				g_PlayerFuncs.SayText(plr, 'Type ".pp" in console for more commands/info\n');
			}
			return true;
		}
		
		if ( args[0] == ".pee" or args[0] == ".bloodpee" )
		{
			float delta = g_Engine.time - state.lastPee;
			if (delta < cvar_pp_cooldown.GetInt()) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCENTER, "Wait " + int((cvar_pp_cooldown.GetInt() - delta) + 0.99f) + " seconds\n");
				return true;
			}
			state.nextPee = getNextAutoPee();
			state.lastPee = g_Engine.time;
			peepee(EHandle(plr), 1.0f, 4, false, args[0] == ".bloodpee");
			return true;
		}
		
		if (args[0] == ".blood") {
			if (g_Engine.time - state.lastBleed < cvar_bleed_cooldown.GetFloat()) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCENTER, "Wait a second\n");
				return true;
			}
			
			bleed(plr);
			return true;
		}
		
		if (args[0] == ".bleed") {
			if (args.ArgC() == 1) {
				state.autoBleed = !state.autoBleed;
			} else {
				state.autoBleed = atoi(args[1]) != 0;
			}
			state.realBleed = false;
			state.lastBleed = g_Engine.time;
			g_PlayerFuncs.SayText(plr, 'Constant bleed ' + (state.autoBleed ? "enabled" : "disabled") + '.\n');
			return true;
		}
		
		if (args[0] == ".bleedhp") {
			if (args.ArgC() == 1) {
				state.realBleed = !state.realBleed;
			} else {
				state.realBleed = atoi(args[1]) != 0;
			}
			state.autoBleed = false;
			state.lastBleed = g_Engine.time;
			g_PlayerFuncs.SayText(plr, 'Low HP bleeding ' + (state.realBleed ? "enabled" : "disabled") + '.\n');
			return true;
		}
		
		if ( args[0] == ".coom" or args[0] == ".bloodcoom" )
		{
			float delta = g_Engine.time - state.lastPee;
			if (delta < cvar_pp_cooldown.GetInt()) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCENTER, "Wait " + int((cvar_pp_cooldown.GetInt() - delta) + 0.99f) + " seconds\n");
				return true;
			}
			state.nextPee = getNextAutoPee();
			state.lastPee = g_Engine.time;
			
			bool isBlood = args[0] == ".bloodcoom";
			
			coom(EHandle(plr), 1.0f, 3, isBlood);
			
			if (plr.IsAlive()) {
				string snd = coom_sounds[Math.RandomLong(0, coom_sounds.size()-1)];
				int pit = Math.RandomLong(95, 105);
				float vol = 0.8f;
				g_SoundSystem.PlaySound(plr.edict(), CHAN_VOICE, snd, vol, 0.8f, 0, pit, 0, true, plr.pev.origin);
			}
			
			return true;
		}
		
		if ( args[0] == ".lactate" || args[0] == ".milk" || args[0] == ".bloodmilk" )
		{
			float delta = g_Engine.time - state.lastPee;
			if (delta < cvar_pp_cooldown.GetInt()) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCENTER, "Wait " + int((cvar_pp_cooldown.GetInt() - delta) + 0.99f) + " seconds\n");
				return true;
			}
			
			int pit = Math.RandomLong(95, 105);
			float vol = 0.8f;
			g_SoundSystem.PlaySound(plr.edict(), CHAN_VOICE, milk_sound, vol, 0.8f, 0, pit, 0, true, plr.pev.origin);
			
			state.nextPee = getNextAutoPee();
			state.lastPee = g_Engine.time;
			lactate(EHandle(plr), 1.0f, 2, args[0] == ".bloodmilk");
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
CClientCommand _coom("coom", "Pee pee poo poo commands", @consoleCmd );
CClientCommand _milk("milk", "Pee pee poo poo commands", @consoleCmd );
CClientCommand _lactate("lactate", "Pee pee poo poo commands", @consoleCmd );
CClientCommand _bleed("bleed", "Pee pee poo poo commands", @consoleCmd );
CClientCommand _bleedhp("bleedhp", "Pee pee poo poo commands", @consoleCmd );
CClientCommand _blood("blood", "Pee pee poo poo commands", @consoleCmd );
CClientCommand _bloodpee("bloodpee", "Pee pee poo poo commands", @consoleCmd );
CClientCommand _bloodcoom("bloodcoom", "Pee pee poo poo commands", @consoleCmd );
CClientCommand _bloodmilk("bloodmilk", "Pee pee poo poo commands", @consoleCmd );

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

void te_decal(Vector pos, CBaseEntity@ brushEnt=null, string decal="{handi",
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_DECAL);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteByte(g_EngineFuncs.DecalIndex(decal));
	m.WriteShort(brushEnt is null ? 0 : brushEnt.entindex());
	m.End();
}
