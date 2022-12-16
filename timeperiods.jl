"""
TimePeriods between two times

ScenarioTimePeriod is used to limit how much data is read into the problem.
The dataset can contain 60 weather years while we only need 30.
For example used in includeRotatingTimeVector!()

TODO: SimulationTimePeriod
"""

# --- ScenarioTimePeriod ---

function includeScenarioTimePeriod!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    start = getdictvalue(value, "Start", DateTime, elkey)
    stop  = getdictvalue(value, "Stop",  DateTime, elkey)
    
    isisoyearstart(start) || error("Start must be isoyearstart for $elkey")
    isisoyearstart(stop)  || error("Stop  must be isoyearstart for $elkey")
    stop > start          || error(             "Stop <= Start for $elkey")
    
    lowlevel[getobjkey(elkey)] = value
    
    return true
end

# --- SimulationTimePeriod ---

function includeSimulationTimePeriod!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)::Bool
    checkkey(lowlevel, elkey)
    
    start = getdictvalue(value, "Start", DateTime, elkey)
    stop  = getdictvalue(value, "Stop",  DateTime, elkey)
    
    stop > start || error("Stop  <= Start for $elkey")
        
    lowlevel[getobjkey(elkey)] = value
    return true
end

INCLUDEELEMENT[TypeKey(TIMEPERIOD_CONCEPT, "ScenarioTimePeriod")] = includeScenarioTimePeriod!
INCLUDEELEMENT[TypeKey(TIMEPERIOD_CONCEPT, "SimulationTimePeriod")] = includeSimulationTimePeriod!