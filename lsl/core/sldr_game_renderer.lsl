//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config_renderer.lslh"
#include "../include/ddr_debug_engine.lslh"
#include "../include/ddr_link_messages.lslh"

#include "ddr_chart_data_renderer.lslh"
#include "ddr_lane_renderer.lslh"

integer gRenderActive = FALSE;
integer gRenderChartReady = FALSE;

integer gRenderSongClockStarted = FALSE;
float gRenderSongClockStartAt = 0.0;

integer ddrRenderClockStart()
{
    gRenderSongClockStartAt = ddrNow() + DDR_PLAY_START_DELAY;
    gRenderSongClockStarted = TRUE;
    return TRUE;
}

integer ddrRenderClockStop()
{
    gRenderSongClockStarted = FALSE;
    return TRUE;
}

float ddrRenderSongTimeNow()
{
    if (!gRenderSongClockStarted)
    {
        return -9999.0;
    }
    return ddrNow() - gRenderSongClockStartAt;
}

integer ddrRenderDetachChart()
{
    return ddrChartDetach();
}

integer ddrRenderStop()
{
    gRenderActive = FALSE;
    gRenderChartReady = FALSE;
    ddrRenderClockStop();
    ddrRenderDetachChart();
    if (gRendererInitialized)
    {
        ddrRendererReset();
    }
    return TRUE;
}

integer ddrRenderHandleChartReady(string payload)
{
    integer seq = (integer)llJsonGetValue(payload, ["seq"]);
    float duration = (float)llJsonGetValue(payload, ["duration"]);
    integer notes = (integer)llJsonGetValue(payload, ["notes"]);

    if (!ddrChartSetLoaded(seq, "", 0, duration, notes, 0))
    {
        ddrDebug("RENDER", "chart metadata failed");
        ddrRenderStop();
        return FALSE;
    }

    gRenderChartReady = TRUE;
    gRenderActive = FALSE;
    if (gRendererInitialized)
    {
        ddrRendererReset();
    }
    ddrDebug(
        "RENDER",
        "chart ready seq=" + (string)seq +
        " notes=" + (string)notes
    );
    return TRUE;
}

integer ddrRenderHandleMainReady()
{
    if (!gRenderChartReady)
    {
        ddrDebug("RENDER", "main-ready without chart");
        return FALSE;
    }
    if (ddrChartNoteCount() <= 0)
    {
        ddrDebug("RENDER", "chart empty");
        ddrRenderStop();
        return FALSE;
    }

    ddrRendererReset();
    ddrRenderClockStart();
    gRenderActive = TRUE;
    return TRUE;
}

integer ddrRenderTick()
{
    if (!gRenderActive)
    {
        return FALSE;
    }

    float songTime = ddrRenderSongTimeNow();
    if (songTime < -DDR_RENDER_LOOKAHEAD_SECONDS)
    {
        return FALSE;
    }

    ddrRendererTick(songTime);
    if (songTime >= (gChartDurationSeconds + DDR_POST_SONG_GRACE_SECONDS + 1.0))
    {
        ddrRenderStop();
    }
    return TRUE;
}

integer ddrRenderBoot()
{
    gRenderActive = FALSE;
    gRenderChartReady = FALSE;
    ddrRenderClockStop();
    ddrRenderDetachChart();
    ddrRendererInit();
    llSetTimerEvent(DDR_TICK_SECONDS);
    return TRUE;
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
        ddrRenderBoot();
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
            if (gRendererInitialized)
            {
                ddrRendererDiscoverSlots();
                ddrRendererReset();
            }
        }
    }

    link_message(integer senderNum, integer num, string str, key id)
    {
        if (num == DDR_LM_RUNTIME_RESET)
        {
            ddrRenderStop();
            return;
        }
        if (num == DDR_LM_RUNTIME_START)
        {
            ddrRenderStop();
            return;
        }
        if (num == DDR_LM_CHART_READY)
        {
            ddrRenderHandleChartReady(str);
            return;
        }
        if (num == DDR_LM_CHART_FAIL)
        {
            ddrRenderStop();
            return;
        }
        if (num == DDR_LM_MAIN_READY)
        {
            ddrRenderHandleMainReady();
            return;
        }
        if (num == DDR_LM_RUNTIME_RESCAN_LINKS)
        {
            if (!gRendererInitialized)
            {
                return;
            }
            ddrRendererDiscoverSlots();
            ddrRendererReset();
            return;
        }
        if (num == DDR_LM_RUNTIME_DEBUG)
        {
            string value = llToLower(llStringTrim(str, STRING_TRIM));
            if (value == "1" || value == "on" || value == "true")
            {
                ddrDebugSet(TRUE);
            }
            else
            {
                ddrDebugSet(FALSE);
            }
            return;
        }
    }

    timer()
    {
        ddrRenderTick();
    }
}
