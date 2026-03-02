//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config.lslh"
#include "../include/ddr_debug.lslh"
#include "../include/ddr_link_messages.lslh"

integer ddrRuntimeStubBoot()
{
    llSetTimerEvent(0.0);
    ddrDebug("RUNTIME", "stub active; gameplay runtime moved to sldr_game_engine.lsl");
    return TRUE;
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
        ddrRuntimeStubBoot();
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
        }
    }

    link_message(integer senderNum, integer num, string str, key id)
    {
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
        }
    }
}
