//mono
#include "../include/ddr_config_scorebar.lslh"
#include "../include/ddr_debug.lslh"
#include "../include/ddr_link_messages.lslh"

integer gScorebarEnabled = FALSE;
integer gScorebarLink = 0;
integer gScorebarVisible = FALSE;
integer gScorebarActive = FALSE;
float gScorebarLastPercent = -1.0;

integer ddrScorebarFindLinkByName(string targetName)
{
    string wanted = llToLower(llStringTrim(targetName, STRING_TRIM));
    if (wanted == "")
    {
        return 0;
    }

    integer linkNum = 1;
    integer primCount = llGetNumberOfPrims();
    for (; linkNum <= primCount; ++linkNum)
    {
        string current = llToLower(llStringTrim(llGetLinkName(linkNum), STRING_TRIM));
        if (current == wanted)
        {
            return linkNum;
        }
    }
    return 0;
}

integer ddrScorebarResolveLink()
{
    integer byName = ddrScorebarFindLinkByName(DDR_SCOREBAR_PRIM_NAME);
    if (byName > 0)
    {
        return byName;
    }
    if (DDR_SCOREBAR_LINK > 0 && DDR_SCOREBAR_LINK <= llGetNumberOfPrims())
    {
        return DDR_SCOREBAR_LINK;
    }
    return 0;
}

string ddrScorebarUrl(float percent)
{
    float clamped = ddrClampFloat(percent, 0.0, 100.0);
    string query = "percent=" + llEscapeURL((string)clamped) + "&ts=" + (string)llGetUnixTime();
    return ddrJoinUrl(DDR_BASE_URL, DDR_PATH_SCOREBAR) + "?" + query;
}

integer ddrScorebarSetVisible(integer visible)
{
    if (!gScorebarEnabled)
    {
        return FALSE;
    }

    float alpha = 0.0;
    if (visible)
    {
        alpha = 1.0;
    }
    llSetLinkPrimitiveParamsFast(
        gScorebarLink,
        [PRIM_COLOR, DDR_SCOREBAR_FACE, <1.0, 1.0, 1.0>, alpha]
    );
    gScorebarVisible = visible;
    return TRUE;
}

integer ddrScorebarSetPercent(float percent)
{
    if (!gScorebarEnabled)
    {
        return FALSE;
    }

    float clamped = ddrClampFloat(percent, 0.0, 100.0);
    if (!gScorebarVisible)
    {
        ddrScorebarSetVisible(TRUE);
    }

    if (llFabs(clamped - gScorebarLastPercent) < 0.001)
    {
        return TRUE;
    }

    string url = ddrScorebarUrl(clamped);
    llSetLinkMedia(
        gScorebarLink,
        DDR_SCOREBAR_FACE,
        [
            PRIM_MEDIA_CURRENT_URL, url,
            PRIM_MEDIA_HOME_URL, url,
            PRIM_MEDIA_AUTO_PLAY, TRUE,
            PRIM_MEDIA_AUTO_SCALE, TRUE
        ]
    );
    gScorebarLastPercent = clamped;
    return TRUE;
}

integer ddrScorebarRequestStatus()
{
    if (!gScorebarEnabled || !gScorebarActive)
    {
        return FALSE;
    }
    llMessageLinked(LINK_SET, DDR_LM_SCORE_STATUS, "", NULL_KEY);
    return TRUE;
}

integer ddrScorebarStart()
{
    if (!gScorebarEnabled)
    {
        return FALSE;
    }
    gScorebarActive = TRUE;
    gScorebarLastPercent = -1.0;
    llSetTimerEvent(DDR_SCOREBAR_UPDATE_SECONDS);
    ddrScorebarRequestStatus();
    return TRUE;
}

integer ddrScorebarStop()
{
    gScorebarActive = FALSE;
    gScorebarLastPercent = -1.0;
    llSetTimerEvent(0.0);
    if (!gScorebarEnabled)
    {
        return FALSE;
    }
    return ddrScorebarSetVisible(FALSE);
}

integer ddrScorebarInit()
{
    gScorebarLink = ddrScorebarResolveLink();
    gScorebarEnabled = (gScorebarLink > 0);
    gScorebarVisible = FALSE;
    gScorebarActive = FALSE;
    gScorebarLastPercent = -1.0;

    if (gScorebarEnabled)
    {
        ddrScorebarSetVisible(FALSE);
        ddrDebug("SCOREBAR", "enabled link=" + (string)gScorebarLink + " face=" + (string)DDR_SCOREBAR_FACE);
    }
    else
    {
        ddrDebug("SCOREBAR", "disabled (name=" + DDR_SCOREBAR_PRIM_NAME + ")");
    }
    return gScorebarEnabled;
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
        ddrScorebarInit();
    }

    on_rez(integer startParam)
    {
        llResetScript();
    }

    changed(integer changeMask)
    {
        if (changeMask & CHANGED_OWNER)
        {
            llResetScript();
            return;
        }
        if (changeMask & CHANGED_LINK)
        {
            ddrScorebarInit();
        }
    }

    link_message(integer senderNum, integer num, string str, key id)
    {
        if (num == DDR_LM_MAIN_READY)
        {
            ddrScorebarStart();
            return;
        }
        if (num == DDR_LM_MAIN_FAIL || num == DDR_LM_MAIN_COMPLETE || num == DDR_LM_MAIN_SCORE_DEPLETED)
        {
            ddrScorebarStop();
            return;
        }
        if (num == DDR_LM_RUNTIME_START || num == DDR_LM_RUNTIME_RESET)
        {
            ddrScorebarStop();
            return;
        }
        if (num == DDR_LM_MAIN_SCORE_STATUS)
        {
            if (gScorebarActive)
            {
                ddrScorebarSetPercent((float)llStringTrim(str, STRING_TRIM));
            }
            return;
        }
    }

    timer()
    {
        ddrScorebarRequestStatus();
    }
}
