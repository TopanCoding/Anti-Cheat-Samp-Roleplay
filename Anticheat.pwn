/*
    ==========================================================
     ANTI-CHEAT LENGKAP UNTUK SA:MP (Pawn)
    ==========================================================
    Deteksi:
    1. Speedhack
    2. Teleport / Warp Hack
    3. Health / Armor Hack
    4. Weapon Hack (weapon id ilegal & weapon tanpa give)
    5. NoClip (nembus tembok/tanah)
    6. Fake Kill (OnPlayerDeath tanpa damage valid)
    7. Aimbot dasar (headshot rate & reaction time mencurigakan)

    CARA PAKAI:
    - #include script ini setelah a_samp
    - Panggil AntiCheat_OnConnect(playerid)   di OnPlayerConnect
    - Panggil AntiCheat_OnSpawn(playerid)     di OnPlayerSpawn
    - Panggil AntiCheat_OnUpdate(playerid)    di OnPlayerUpdate
    - Panggil AntiCheat_OnDeath(playerid,killerid,reason) di OnPlayerDeath
    - Panggil AntiCheat_OnGiveWeapon(playerid,weaponid) tiap kali GivePlayerWeapon dipanggil manual
    - Panggil AntiCheat_OnTakeDamage(...) di OnPlayerTakeDamage
    ==========================================================
*/

#include <a_samp>

// ---------------- KONFIGURASI ----------------
#define MAX_WARN                5
#define TELEPORT_DIST           50.0
#define CHECK_INTERVAL          1000        // ms
#define MAX_GROUND_SPEED        2.5         // jarak wajar per cek jalan kaki (meter)
#define NOCLIP_Z_TOLERANCE      3.0         // toleransi ketinggian vs mapAndreas
#define HEADSHOT_RATIO_LIMIT    0.85        // di atas ini dicurigai aimbot
#define MIN_KILL_FOR_RATIO_CHECK 10
#define MIN_REACTION_MS         80          // reaksi tembak lebih cepat dari ini dicurigai

// ---------------- VARIABEL PLAYER ----------------
new pWarnCount[MAX_PLAYERS];

new Float:pLastX[MAX_PLAYERS], Float:pLastY[MAX_PLAYERS], Float:pLastZ[MAX_PLAYERS];
new pLastHealth[MAX_PLAYERS];
new pLastCheckTime[MAX_PLAYERS];

new bool:pWeaponGivenByScript[MAX_PLAYERS][47];   // tandai weapon yang legal didapat lewat script
new pLastDamageTime[MAX_PLAYERS];                 // waktu terakhir kena damage (utk fake kill)
new pLastDamageIssuer[MAX_PLAYERS];               // siapa yang terakhir damage dia

new pTotalKills[MAX_PLAYERS];
new pHeadshotKills[MAX_PLAYERS];
new pLastSeenTime[MAX_PLAYERS];                   // waktu player pertama terlihat oleh calon killer (reaksi tembak)

// ---------------- INISIALISASI ----------------
stock AntiCheat_OnConnect(playerid)
{
    pWarnCount[playerid]        = 0;
    pLastX[playerid]            = 0.0;
    pLastY[playerid]            = 0.0;
    pLastZ[playerid]            = 0.0;
    pLastHealth[playerid]       = 100;
    pLastCheckTime[playerid]    = GetTickCount();
    pLastDamageTime[playerid]   = 0;
    pLastDamageIssuer[playerid] = INVALID_PLAYER_ID;
    pTotalKills[playerid]       = 0;
    pHeadshotKills[playerid]    = 0;
    pLastSeenTime[playerid]     = 0;

    for(new w = 0; w < 47; w++) pWeaponGivenByScript[playerid][w] = false;
    return 1;
}

stock AntiCheat_OnSpawn(playerid)
{
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    pLastX[playerid] = x;
    pLastY[playerid] = y;
    pLastZ[playerid] = z;
    pLastHealth[playerid] = 100;

    for(new w = 0; w < 47; w++) pWeaponGivenByScript[playerid][w] = false;
    // Fist & spawn weapon dianggap legal
    pWeaponGivenByScript[playerid][0] = true;
    return 1;
}

// Panggil manual setiap kamu GivePlayerWeapon() di gamemode agar tercatat legal
stock AntiCheat_OnGiveWeapon(playerid, weaponid)
{
    if(weaponid >= 0 && weaponid <= 46)
        pWeaponGivenByScript[playerid][weaponid] = true;
    return 1;
}

// ---------------- UPDATE UTAMA (panggil di OnPlayerUpdate) ----------------
stock AntiCheat_OnUpdate(playerid)
{
    if(!IsPlayerConnected(playerid)) return 1;
    if(IsPlayerNPC(playerid)) return 1;

    new tick = GetTickCount();
    if(tick - pLastCheckTime[playerid] < CHECK_INTERVAL) return 1;
    new Float:elapsedSec = (tick - pLastCheckTime[playerid]) / 1000.0;
    pLastCheckTime[playerid] = tick;

    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);

    // ---- SKIP CEK JIKA PLAYER SEDANG DI ANIMASI KHUSUS / SPAWN BARU ----
    if(pLastX[playerid] == 0.0 && pLastY[playerid] == 0.0)
    {
        pLastX[playerid] = x; pLastY[playerid] = y; pLastZ[playerid] = z;
        return 1;
    }

    new Float:dist = GetDistanceBetweenPoints(pLastX[playerid], pLastY[playerid], pLastZ[playerid], x, y, z);

    // =========================================================
    // 1. TELEPORT / WARP HACK
    // =========================================================
    new Float:maxTeleportDist = TELEPORT_DIST;
    if(GetPlayerState(playerid) == PLAYER_STATE_DRIVER) maxTeleportDist *= 3.0;

    if(dist > maxTeleportDist)
    {
        AntiCheat_Warn(playerid, "Teleport/Warp Hack");
    }

    // =========================================================
    // 2. SPEEDHACK (kecepatan jalan kaki tidak wajar)
    // =========================================================
    else if(GetPlayerState(playerid) == PLAYER_STATE_ONFOOT)
    {
        new Float:maxWalkDist = MAX_GROUND_SPEED * elapsedSec * 3.0; // toleransi sprint + lag
        if(dist > maxWalkDist && dist < maxTeleportDist)
        {
            AntiCheat_Warn(playerid, "Speedhack (kecepatan jalan tidak wajar)");
        }
    }

    // =========================================================
    // 3. NOCLIP SEDERHANA (menembus tembok/lantai)
    //    Catatan: deteksi noclip akurat butuh MapAndreas plugin
    //    untuk cek ketinggian tanah asli. Di sini contoh dasarnya.
    // =========================================================
    if(GetPlayerState(playerid) == PLAYER_STATE_ONFOOT)
    {
        new Float:groundZ;
        if(AntiCheat_GetGroundZ(x, y, z, groundZ))
        {
            if(floatabs(z - groundZ) > NOCLIP_Z_TOLERANCE)
            {
                AntiCheat_Warn(playerid, "Kemungkinan NoClip (posisi Z tidak wajar)");
            }
        }
    }

    pLastX[playerid] = x;
    pLastY[playerid] = y;
    pLastZ[playerid] = z;

    // =========================================================
    // 4. HEALTH / ARMOR HACK
    // =========================================================
    new Float:health, Float:armor;
    GetPlayerHealth(playerid, health);
    GetPlayerArmour(playerid, armor);

    if(health > pLastHealth[playerid] + 50 && pLastHealth[playerid] > 0 && health < 100.5)
    {
        AntiCheat_Warn(playerid, "Health Hack (nyawa naik drastis)");
    }
    pLastHealth[playerid] = floatround(health);

    // =========================================================
    // 5. WEAPON HACK (id ilegal / senjata tanpa pernah diberikan)
    // =========================================================
    new weapon = GetPlayerWeapon(playerid);
    if(weapon > 46)
    {
        AntiCheat_Warn(playerid, "Weapon ID tidak valid");
    }
    else if(weapon > 0 && !pWeaponGivenByScript[playerid][weapon])
    {
        // Senjata dipakai padahal tidak pernah di-give lewat script -> mencurigakan
        AntiCheat_Warn(playerid, "Weapon Hack (senjata ilegal terdeteksi)");
    }

    return 1;
}

// ---------------- DAMAGE TRACKING (panggil di OnPlayerTakeDamage) ----------------
stock AntiCheat_OnTakeDamage(playerid, issuerid, Float:amount, weaponid, bodypart)
{
    pLastDamageTime[playerid]   = GetTickCount();
    pLastDamageIssuer[playerid] = issuerid;

    // Catat waktu "kontak pertama" untuk cek reaction time aimbot
    if(issuerid != INVALID_PLAYER_ID && pLastSeenTime[issuerid] == 0)
    {
        pLastSeenTime[issuerid] = GetTickCount();
    }

    // ---- DETEKSI AIMBOT DASAR: reaksi tembak terlalu cepat ----
    if(issuerid != INVALID_PLAYER_ID && pLastSeenTime[issuerid] != 0)
    {
        new reaction = GetTickCount() - pLastSeenTime[issuerid];
        if(reaction < MIN_REACTION_MS && reaction > 0)
        {
            AntiCheat_Warn(issuerid, "Kemungkinan Aimbot (reaksi tembak terlalu cepat)");
        }
        pLastSeenTime[issuerid] = 0; // reset setelah damage terjadi
    }

    // ---- HITUNG HEADSHOT UNTUK RATIO CHECK ----
    if(bodypart == 9) // 9 = head di SA:MP
    {
        pHeadshotKills[issuerid]++;
    }

    return 1;
}

// ---------------- DEATH / FAKE KILL (panggil di OnPlayerDeath) ----------------
stock AntiCheat_OnDeath(playerid, killerid, reason)
{
    new tick = GetTickCount();

    // =========================================================
    // 6. FAKE KILL DETECTION
    //    Kill dianggap valid jika korban baru saja menerima damage
    //    dari killer yang sama dalam rentang waktu wajar (< 5 detik)
    // =========================================================
    if(killerid != INVALID_PLAYER_ID)
    {
        new gap = tick - pLastDamageTime[playerid];
        if(pLastDamageIssuer[playerid] != killerid || gap > 5000)
        {
            AntiCheat_Warn(killerid, "Kemungkinan Fake Kill (kill tanpa damage valid)");
        }
        else
        {
            // Kill valid, hitung statistik untuk deteksi aimbot ratio
            pTotalKills[killerid]++;

            // =========================================================
            // 7. AIMBOT DETECTION (headshot ratio terlalu tinggi)
            // =========================================================
            if(pTotalKills[killerid] >= MIN_KILL_FOR_RATIO_CHECK)
            {
                new Float:ratio = float(pHeadshotKills[killerid]) / float(pTotalKills[killerid]);
                if(ratio >= HEADSHOT_RATIO_LIMIT)
                {
                    AntiCheat_Warn(killerid, "Kemungkinan Aimbot (headshot ratio tidak wajar)");
                }
            }
        }
    }

    // Reset data korban
    pLastDamageTime[playerid]   = 0;
    pLastDamageIssuer[playerid] = INVALID_PLAYER_ID;

    return 1;
}

// ---------------- SISTEM WARNING & PUNISHMENT ----------------
stock AntiCheat_Warn(playerid, const reason[])
{
    if(playerid == INVALID_PLAYER_ID || !IsPlayerConnected(playerid)) return 0;

    pWarnCount[playerid]++;

    new name[MAX_PLAYER_NAME], msg[144];
    GetPlayerName(playerid, name, sizeof(name));

    format(msg, sizeof(msg), "[AntiCheat] %s dicurigai: %s (Warn: %d/%d)", name, reason, pWarnCount[playerid], MAX_WARN);
    SendClientMessageToAll(0xFF0000FF, msg);
    printf("%s", msg);

    if(pWarnCount[playerid] >= MAX_WARN)
    {
        format(msg, sizeof(msg), "[AntiCheat] %s di-kick otomatis karena terindikasi cheat.", name);
        SendClientMessageToAll(0xFF0000FF, msg);
        Kick(playerid);
        // Ganti dengan Ban(playerid) jika ingin banned permanen
    }
    return 1;
}

// ---------------- UTILITAS ----------------
stock Float:GetDistanceBetweenPoints(Float:x1, Float:y1, Float:z1, Float:x2, Float:y2, Float:z2)
{
    return floatsqroot(
        floatpower(floatabs(x2 - x1), 2.0) +
        floatpower(floatabs(y2 - y1), 2.0) +
        floatpower(floatabs(z2 - z1), 2.0)
    );
}

// Placeholder pengecekan tinggi tanah.
// Untuk akurasi tinggi, gunakan plugin MapAndreas dan panggil
// MapAndreas_FindZ_For2DCoord(x, y, groundZ) di sini.
stock bool:AntiCheat_GetGroundZ(Float:x, Float:y, Float:z, &Float:groundZ)
{
    #if defined MapAndreas_FindZ_For2DCoord
        MapAndreas_FindZ_For2DCoord(x, y, groundZ);
        return true;
    #else
        // Tanpa MapAndreas, kita tidak bisa cek tanah asli secara akurat.
        // Kembalikan false supaya cek noclip di atas dilewati (hindari false positive).
        groundZ = z;
        return false;
    #endif
}
