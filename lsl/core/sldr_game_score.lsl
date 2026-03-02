//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config_engine.lslh"
#include "../include/ddr_debug_engine.lslh"
#include "../include/ddr_link_messages.lslh"

integer gScorePoints = 0;
integer gMaxPossiblePoints = 0;
integer gCombo = 0;
integer gMaxCombo = 0;

integer gJudgePerfect = 0;
integer gJudgeGreat = 0;
integer gJudgeGood = 0;
integer gJudgeBoo = 0;
integer gJudgeMiss = 0;

integer gHoldOk = 0;
integer gHoldNg = 0;

integer gMetricHitNotes = 0;
integer gMetricChordTotalNotes = 0;
integer gMetricChordHitNotes = 0;
integer gMetricOffbeatTotalNotes = 0;
integer gMetricOffbeatHitNotes = 0;

integer gChartTotalNotes = 0;
integer gChartTotalHolds = 0;
integer gChartMeter = 0;

string gSongId = "";
string gSongTitle = "";
string gSongArtist = "";
string gSongDifficulty = "";
list gSongRadar = [0.0, 0.0, 0.0, 0.0, 0.0];

string ddrJsonField(string payload, string fieldName)
{
    string value = llJsonGetValue(payload, [fieldName]);
    if (value == JSON_INVALID)
    {
        return "";
    }
    return value;
}

integer ddrScoreSvcResetCounters()
{
    gScorePoints = 0;
    gMaxPossiblePoints = 0;
    gCombo = 0;
    gMaxCombo = 0;

    gJudgePerfect = 0;
    gJudgeGreat = 0;
    gJudgeGood = 0;
    gJudgeBoo = 0;
    gJudgeMiss = 0;

    gHoldOk = 0;
    gHoldNg = 0;

    gMetricHitNotes = 0;
    gMetricChordTotalNotes = 0;
    gMetricChordHitNotes = 0;
    gMetricOffbeatTotalNotes = 0;
    gMetricOffbeatHitNotes = 0;
    return TRUE;
}

integer ddrScoreSvcResetAll()
{
    ddrScoreSvcResetCounters();
    gChartTotalNotes = 0;
    gChartTotalHolds = 0;
    gChartMeter = 0;
    gSongId = "";
    gSongTitle = "";
    gSongArtist = "";
    gSongDifficulty = "";
    gSongRadar = [0.0, 0.0, 0.0, 0.0, 0.0];
    return TRUE;
}

list ddrScoreSvcParseRadar(string radarJson)
{
    list out = [0.0, 0.0, 0.0, 0.0, 0.0];
    if (radarJson == "" || llJsonValueType(radarJson, []) != JSON_ARRAY)
    {
        return out;
    }

    list values = llJson2List(radarJson);
    integer i = 0;
    integer maxCopy = llGetListLength(values);
    if (maxCopy > 5)
    {
        maxCopy = 5;
    }

    for (; i < maxCopy; ++i)
    {
        float value = ddrClampFloat((float)llList2String(values, i), 0.0, 1.0);
        out = llListReplaceList(out, [value], i, i);
    }
    return out;
}

integer ddrScoreSvcStart(string payload)
{
    ddrScoreSvcResetCounters();

    gSongId = ddrJsonField(payload, "songId");
    gSongTitle = ddrJsonField(payload, "title");
    gSongArtist = ddrJsonField(payload, "artist");
    gSongDifficulty = ddrJsonField(payload, "difficulty");

    gChartMeter = (integer)ddrJsonField(payload, "meter");
    gChartTotalNotes = (integer)ddrJsonField(payload, "noteCount");
    gChartTotalHolds = (integer)ddrJsonField(payload, "holdCount");
    gMetricChordTotalNotes = (integer)ddrJsonField(payload, "chordTotal");
    gMetricOffbeatTotalNotes = (integer)ddrJsonField(payload, "offbeatTotal");
    gSongRadar = ddrScoreSvcParseRadar(ddrJsonField(payload, "songRadar"));

    gMaxPossiblePoints = (gChartTotalNotes * DDR_POINTS_PERFECT) + (gChartTotalHolds * DDR_POINTS_HOLD_OK);
    return TRUE;
}

integer ddrScoreSvcPointsForJudge(integer judgement)
{
    if (judgement == DDR_JUDGE_PERFECT)
    {
        return DDR_POINTS_PERFECT;
    }
    if (judgement == DDR_JUDGE_GREAT)
    {
        return DDR_POINTS_GREAT;
    }
    if (judgement == DDR_JUDGE_GOOD)
    {
        return DDR_POINTS_GOOD;
    }
    if (judgement == DDR_JUDGE_BOO)
    {
        return DDR_POINTS_BOO;
    }
    return DDR_POINTS_MISS;
}

integer ddrScoreSvcApplyNote(integer judgement, integer noteFlags)
{
    gScorePoints += ddrScoreSvcPointsForJudge(judgement);

    if (judgement == DDR_JUDGE_PERFECT)
    {
        ++gJudgePerfect;
        ++gCombo;
    }
    else if (judgement == DDR_JUDGE_GREAT)
    {
        ++gJudgeGreat;
        ++gCombo;
    }
    else if (judgement == DDR_JUDGE_GOOD)
    {
        ++gJudgeGood;
        ++gCombo;
    }
    else if (judgement == DDR_JUDGE_BOO)
    {
        ++gJudgeBoo;
        gCombo = 0;
    }
    else
    {
        ++gJudgeMiss;
        gCombo = 0;
    }

    if (gCombo > gMaxCombo)
    {
        gMaxCombo = gCombo;
    }

    if (judgement <= DDR_JUDGE_GOOD)
    {
        ++gMetricHitNotes;
        if (noteFlags & DDR_NOTE_FLAG_CHORD)
        {
            ++gMetricChordHitNotes;
        }
        if (noteFlags & DDR_NOTE_FLAG_OFFBEAT)
        {
            ++gMetricOffbeatHitNotes;
        }
    }
    return TRUE;
}

integer ddrScoreSvcApplyHold(integer holdState)
{
    if (holdState == DDR_HOLD_STATE_OK)
    {
        ++gHoldOk;
        gScorePoints += DDR_POINTS_HOLD_OK;
    }
    else if (holdState == DDR_HOLD_STATE_NG)
    {
        ++gHoldNg;
        gScorePoints += DDR_POINTS_HOLD_NG;
        gCombo = 0;
    }
    return TRUE;
}

float ddrScoreSvcPercent()
{
    if (gMaxPossiblePoints <= 0)
    {
        return 0.0;
    }
    return ddrClampFloat((100.0 * (float)gScorePoints) / (float)gMaxPossiblePoints, 0.0, 100.0);
}

string ddrScoreSvcGrade()
{
    float pct = ddrScoreSvcPercent();
    if (pct >= DDR_GRADE_A)
    {
        return "A";
    }
    if (pct >= DDR_GRADE_B)
    {
        return "B";
    }
    if (pct >= DDR_GRADE_C)
    {
        return "C";
    }
    if (pct >= DDR_GRADE_D)
    {
        return "D";
    }
    if (pct >= DDR_GRADE_E)
    {
        return "E";
    }
    return "F";
}

list ddrScoreSvcPerformanceRadar()
{
    float stream = 0.0;
    float voltage = 0.0;
    float air = 1.0;
    float freeze = 1.0;
    float chaos = 1.0;

    if (gChartTotalNotes > 0)
    {
        stream = ddrClampFloat((float)gMetricHitNotes / (float)gChartTotalNotes, 0.0, 1.0);
        voltage = ddrClampFloat((float)gMaxCombo / (float)gChartTotalNotes, 0.0, 1.0);
    }
    if (gMetricChordTotalNotes > 0)
    {
        air = ddrClampFloat((float)gMetricChordHitNotes / (float)gMetricChordTotalNotes, 0.0, 1.0);
    }
    if (gChartTotalHolds > 0)
    {
        freeze = ddrClampFloat((float)gHoldOk / (float)gChartTotalHolds, 0.0, 1.0);
    }
    if (gMetricOffbeatTotalNotes > 0)
    {
        chaos = ddrClampFloat((float)gMetricOffbeatHitNotes / (float)gMetricOffbeatTotalNotes, 0.0, 1.0);
    }
    return [stream, voltage, air, freeze, chaos];
}

string ddrScoreSvcBuildPayload()
{
    string payload = "{}";
    payload = llJsonSetValue(payload, ["songId"], gSongId);
    payload = llJsonSetValue(payload, ["title"], gSongTitle);
    payload = llJsonSetValue(payload, ["artist"], gSongArtist);
    payload = llJsonSetValue(payload, ["difficulty"], gSongDifficulty);
    payload = llJsonSetValue(payload, ["meter"], (string)gChartMeter);
    payload = llJsonSetValue(payload, ["score"], (string)gScorePoints);
    payload = llJsonSetValue(payload, ["percent"], (string)ddrScoreSvcPercent());
    payload = llJsonSetValue(payload, ["grade"], ddrScoreSvcGrade());
    payload = llJsonSetValue(payload, ["comboMax"], (string)gMaxCombo);

    payload = llJsonSetValue(payload, ["judgements", "perfect"], (string)gJudgePerfect);
    payload = llJsonSetValue(payload, ["judgements", "great"], (string)gJudgeGreat);
    payload = llJsonSetValue(payload, ["judgements", "good"], (string)gJudgeGood);
    payload = llJsonSetValue(payload, ["judgements", "boo"], (string)gJudgeBoo);
    payload = llJsonSetValue(payload, ["judgements", "miss"], (string)gJudgeMiss);

    payload = llJsonSetValue(payload, ["holds", "ok"], (string)gHoldOk);
    payload = llJsonSetValue(payload, ["holds", "ng"], (string)gHoldNg);

    payload = llJsonSetValue(payload, ["radar", "song"], llList2Json(JSON_ARRAY, gSongRadar));
    payload = llJsonSetValue(payload, ["radar", "performance"], llList2Json(JSON_ARRAY, ddrScoreSvcPerformanceRadar()));
    return payload;
}

integer ddrScoreSvcFinish()
{
    llMessageLinked(LINK_SET, DDR_LM_MAIN_COMPLETE, ddrScoreSvcBuildPayload(), NULL_KEY);
    return TRUE;
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
        ddrScoreSvcResetAll();
        ddrDebug("SCORE", "booted; free memory=" + (string)llGetFreeMemory());
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
    }

    link_message(integer senderNum, integer num, string str, key id)
    {
        if (num == DDR_LM_RUNTIME_RESET || num == DDR_LM_SCORE_RESET)
        {
            ddrScoreSvcResetAll();
            return;
        }
        if (num == DDR_LM_SCORE_START)
        {
            ddrScoreSvcStart(str);
            return;
        }
        if (num == DDR_LM_SCORE_NOTE)
        {
            list parts = llParseStringKeepNulls(str, ["|"], []);
            integer judgement = (integer)llList2String(parts, 0);
            integer noteFlags = (integer)llList2String(parts, 1);
            ddrScoreSvcApplyNote(judgement, noteFlags);
            return;
        }
        if (num == DDR_LM_SCORE_HOLD)
        {
            ddrScoreSvcApplyHold((integer)str);
            return;
        }
        if (num == DDR_LM_SCORE_FINISH)
        {
            ddrScoreSvcFinish();
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
}
