//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config.lslh"
#include "../include/ddr_debug.lslh"
#include "../include/ddr_link_messages.lslh"

#include "ddr_chart_data_loader.lslh"
#include "ddr_lane_renderer.lslh"

integer gRenderActive = FALSE;
integer gRenderLoading = FALSE;
integer gRenderSystemsReady = FALSE;
key gRenderChartRequestId = NULL_KEY;

string gRenderChartUrl = "";

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

integer ddrRenderEnsureSystemsReady()
{
    if (gRenderSystemsReady)
    {
        return TRUE;
    }

    ddrRendererInit();
    gRenderSystemsReady = TRUE;
    ddrDebug("RENDER", "systems ready; free memory=" + (string)llGetFreeMemory());
    return TRUE;
}

integer ddrRenderStop()
{
    gRenderActive = FALSE;
    gRenderLoading = FALSE;
    gRenderChartRequestId = NULL_KEY;
    ddrRenderClockStop();
    ddrChartReset();
    if (gRenderSystemsReady)
    {
        ddrRendererReset();
    }
    return TRUE;
}

integer ddrRenderRequestChart()
{
    if (gRenderChartUrl == "")
    {
        return FALSE;
    }
    gRenderChartRequestId = llHTTPRequest(
        gRenderChartUrl,
        [
            HTTP_METHOD, "GET",
            HTTP_MIMETYPE, "text/plain"
        ],
        ""
    );
    if (gRenderChartRequestId == NULL_KEY)
    {
        return FALSE;
    }
    return TRUE;
}

integer ddrRenderStartFromPayload(string payload)
{
    string chartUrl = llJsonGetValue(payload, ["chartUrl"]);
    if (chartUrl == JSON_INVALID || chartUrl == "")
    {
        ddrDebug("RENDER", "missing chart url");
        return FALSE;
    }

    ddrRenderEnsureSystemsReady();
    ddrRenderStop();

    gRenderChartUrl = chartUrl;
    gRenderLoading = TRUE;
    if (!ddrRenderRequestChart())
    {
        gRenderLoading = FALSE;
        ddrDebug("RENDER", "chart request failed");
        return FALSE;
    }
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
    gRenderSystemsReady = FALSE;
    gRenderActive = FALSE;
    gRenderLoading = FALSE;
    gRenderChartRequestId = NULL_KEY;
    gRenderChartUrl = "";
    ddrRenderClockStop();
    ddrChartReset();
    llSetTimerEvent(DDR_TICK_SECONDS);
    ddrDebug("RENDER", "booted; free memory=" + (string)llGetFreeMemory());
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
            if (gRenderSystemsReady)
            {
                ddrRendererDiscoverSlots();
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
            ddrRenderStartFromPayload(str);
            return;
        }
        if (num == DDR_LM_RUNTIME_RESCAN_LINKS)
        {
            if (!gRenderSystemsReady)
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

    http_response(key requestId, integer status, list metadata, string body)
    {
        if (requestId != gRenderChartRequestId)
        {
            return;
        }

        gRenderChartRequestId = NULL_KEY;
        if (!gRenderLoading)
        {
            return;
        }

        if (status < 200 || status >= 300)
        {
            gRenderLoading = FALSE;
            ddrDebug("RENDER", "chart http fail " + (string)status);
            return;
        }
        if (!ddrChartLoadFromCompactJson(body))
        {
            gRenderLoading = FALSE;
            ddrDebug("RENDER", "chart parse fail");
            return;
        }

        ddrRendererReset();
        ddrRenderClockStart();
        gRenderLoading = FALSE;
        gRenderActive = TRUE;
    }

    timer()
    {
        ddrRenderTick();
    }
}
