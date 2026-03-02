//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config_fx.lslh"
#include "../include/ddr_debug_engine.lslh"
#include "../include/ddr_link_messages.lslh"

#include "ddr_combo_feedback.lslh"
#include "ddr_judge_feedback.lslh"

integer ddrFxReset()
{
    ddrComboFeedbackInit();
    ddrJudgeFeedbackInit();
    ddrComboFeedbackHide();
    ddrJudgeFeedbackHide();
    return TRUE;
}

integer ddrFxHandleNote(string payload)
{
    list parts = llParseStringKeepNulls(payload, ["|"], []);
    integer judgement = (integer)llList2String(parts, 0);
    integer comboValue = (integer)llList2String(parts, 1);
    ddrComboFeedbackOnNoteJudge(judgement, comboValue);
    return TRUE;
}

integer ddrFxHandleHold(string payload)
{
    list parts = llParseStringKeepNulls(payload, ["|"], []);
    integer holdState = (integer)llList2String(parts, 0);
    integer comboValue = (integer)llList2String(parts, 1);
    ddrComboFeedbackOnHoldResult(holdState, comboValue);
    return TRUE;
}

integer ddrFxBoot()
{
    ddrFxReset();
    llSetTimerEvent(DDR_TICK_SECONDS);
    ddrDebug("FX", "booted; free memory=" + (string)llGetFreeMemory());
    return TRUE;
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
        ddrFxBoot();
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
            ddrFxReset();
            return;
        }
    }

    link_message(integer senderNum, integer num, string str, key id)
    {
        if (num == DDR_LM_FX_RESET || num == DDR_LM_RUNTIME_RESET || num == DDR_LM_RUNTIME_RESCAN_LINKS)
        {
            ddrFxReset();
            return;
        }
        if (num == DDR_LM_FX_HIDE_COMBO)
        {
            ddrComboFeedbackHide();
            return;
        }
        if (num == DDR_LM_FX_HIDE_JUDGE)
        {
            ddrJudgeFeedbackHide();
            return;
        }
        if (num == DDR_LM_FX_NOTE)
        {
            ddrFxHandleNote(str);
            return;
        }
        if (num == DDR_LM_FX_HOLD)
        {
            ddrFxHandleHold(str);
            return;
        }
        if (num == DDR_LM_FX_JUDGE)
        {
            ddrJudgeFeedbackShowJudge((integer)str);
            return;
        }
        if (num == DDR_LM_FX_HOLD_JUDGE)
        {
            ddrJudgeFeedbackShowHold((integer)str);
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
        ddrComboFeedbackTick();
        ddrJudgeFeedbackTick();
    }
}
