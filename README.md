# Anti-Cheat-Samp-Roleplay
Free
public OnPlayerConnect(playerid)
{
    AntiCheat_OnConnect(playerid);
    return 1;
}

public OnPlayerSpawn(playerid)
{
    AntiCheat_OnSpawn(playerid);
    return 1;
}

public OnPlayerUpdate(playerid)
{
    AntiCheat_OnUpdate(playerid);
    return 1;
}

public OnPlayerTakeDamage(playerid, issuerid, Float:amount, weaponid, bodypart)
{
    AntiCheat_OnTakeDamage(playerid, issuerid, amount, weaponid, bodypart);
    return 1;
}

public OnPlayerDeath(playerid, killerid, reason)
{
    AntiCheat_OnDeath(playerid, killerid, reason);
    return 1;
}

// Setiap kamu manual GivePlayerWeapon(playerid, WEAPON_XX, ammo);
// tambahkan baris ini tepat setelahnya:
AntiCheat_OnGiveWeapon(playerid, WEAPON_XX);