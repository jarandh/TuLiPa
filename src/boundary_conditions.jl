"""
We want to have a modular system for boundary conditions that work 
with different types of model objects that have one or more state variables. 
 
Different objects could be 
   Storage       - One state variable representing storage content at end of period
   RampUp        - One state variable representing flow in previous period
   TimeDelayFlow - Many state variables representing flow in previous periods

We assume that if an object that have state variables support a 
few functions, which can give sufficient information about variables 
and constraints related to its states, then we should be able to 
use this interface to define general boundary conditions.

We want to implement different types of boundary conditions
   StartEqualStop - Ingoing state equal to outgoing state for each state variable
   SingleCuts     - Future cost variable constrained by optimality cuts 
   MultiCuts      - Future cost variables for scenarios with probability weights constrained by optimality cuts
   ValueTerms     - sum vi * xi where xi are segments of state space of outgoing state variable x, 
                     and vi is marginal value at each segment

Simplifying assumptions:
   We always use variables for incoming states, even though we sometimes could have used constant rhs terms.
   We always represent problems as minimization problems. 

Possible challenges:
   What to do if time delay and hourly master problem and 2-hourly subproblem? 
   Then time indexes for state variables does not have the same meaning in the two problems. 
   Similar issue if subproblem use non-sequential horizon.

We implement NoInitialCondition, NoTerminalCondition, NoBoundaryCondition, StartEqualStop,
ConnectTwoObjects and SimpleSingleCuts

NoInitialCondition, NoTerminalCondition, NoBoundaryCondition are simple types for turning off requirement 
that all objects with state variables should have boundary conditions

StartEqualStop adds an equation to set the start and end state variables equal to each other

ConnectTwoObjects connects the terminal statevariable of one object with the initial state variable of
another object. This boundary condition gives the possibility to make stochastic two-stage problems, where the
reservoirs in the first stage are connected to the reservoir in the second stage scenarios.

SimpleSingleCuts is a modelobject for adding Benders cuts to a problem. It preallocates a fixed number of cuts
that can be activated. SimpleSingleCuts does not support cut selection.
"""

# Interface for objects that are boundary condition types
isboundarycondition(obj) = isinitialcondition(obj) || isterminalcondition(obj)

# A boundary condition can be one or both, but not none
isinitialcondition(::Any) = false
isterminalcondition(::Any) = false

# So we can find which objects have boundary conditions
# E.g. we want to be able to group all objects not already having a 
# boundary condition and use optimality cuts for these
getobjects(::BoundaryCondition) = error("Must implement")

# ---- NoInitialCondition, NoTerminalCondition and NoBoundaryCondition <: BoundaryCondition ---

struct NoInitialCondition <: BoundaryCondition
    id::Id
    object::Any
end

struct NoTerminalCondition <: BoundaryCondition
    id::Id
    object::Any
end

struct NoBoundaryCondition <: BoundaryCondition
    id::Id
    object::Any
end

const _NoBoundaryConditionTypes = Union{NoInitialCondition, NoTerminalCondition, NoBoundaryCondition}

getid(x::_NoBoundaryConditionTypes) = x.id
getobjects(x::_NoBoundaryConditionTypes) = [x.object]
build!(::Prob, ::_NoBoundaryConditionTypes) = nothing
setconstants!(::Prob, ::_NoBoundaryConditionTypes) = nothing
update!(::Prob, ::_NoBoundaryConditionTypes, ::ProbTime) = nothing

isinitialcondition(::NoInitialCondition)  = true
isterminalcondition(::NoTerminalCondition) = true
isinitialcondition(::NoBoundaryCondition)  = true
isterminalcondition(::NoBoundaryCondition) = true

# ---- StartEqualStop <: BoundaryCondition ---

struct StartEqualStop <: BoundaryCondition
    id::Id
    object::Any
    function StartEqualStop(object) # after assemble of all objects
        @assert length(getstatevariables(object)) > 0
        id = Id(BOUNDARYCONDITION_CONCEPT, getinstancename(getid(object)))
        return new(id, object)
    end
    function StartEqualStop(id, object) # before assemble so no checks
        return new(id, object)
    end
end

getid(x::StartEqualStop) = x.id
geteqid(x::StartEqualStop) = Id(BOUNDARYCONDITION_CONCEPT, string("Eq", getinstancename(getid(x))))

getobjects(x::StartEqualStop) = [x.object]
getparent(x::StartEqualStop) = x.object

isinitialcondition(::StartEqualStop)  = true
isterminalcondition(::StartEqualStop) = true

function build!(p::Prob, x::StartEqualStop)
    N = length(getstatevariables(x.object))
    addeq!(p, geteqid(x), N)
    return
end

function setconstants!(p::Prob, x::StartEqualStop)
    for (eq_ix, var) in enumerate(getstatevariables(x.object))
        (id_out, ix_out) = getvarout(var)
        (id_in, ix_in) = getvarin(var)
        setconcoeff!(p, geteqid(x), id_out, eq_ix, ix_out,  1.0)
        setconcoeff!(p, geteqid(x),  id_in, eq_ix,  ix_in, -1.0)
    end
    return 
end

update!(::Prob, ::StartEqualStop, ::ProbTime) = nothing

# Assemble - dependent on storage balance to be assembled (wont work if no state-variables, but not really necessary for assembling)
function assemble!(x::StartEqualStop)::Bool
    isnothing(gethorizon(getbalance(getparent(x)))) && return false
    return true
end

# Include dataelement
function includeStartEqualStop!(toplevel::Dict, ::Dict, elkey::ElementKey, value::Dict)::Bool
    varname    = getdictvalue(value, WHICHINSTANCE, String, elkey)
    varconcept = getdictvalue(value, WHICHCONCEPT,  String, elkey)
    varkey = Id(varconcept, varname)
    haskey(toplevel, varkey) || return false

    var = toplevel[varkey]

    id = getobjkey(elkey)

    toplevel[id] = StartEqualStop(id, var)
    
    return true    
end

INCLUDEELEMENT[TypeKey(BOUNDARYCONDITION_CONCEPT, "StartEqualStop")] = includeStartEqualStop!

# ---- ConnectTwoObjects <: BoundaryCondition ---

struct ConnectTwoObjects <: BoundaryCondition
    id::Id
    outobject::Any # object with outgoing state variable
    inobject::Any # object with ingoing state variable
    function ConnectTwoObjects(outobject, inobject) # after assemble of all objects
        @assert length(getstatevariables(outobject)) > 0
        @assert length(getstatevariables(outobject)) == length(getstatevariables(inobject))

        id = Id(BOUNDARYCONDITION_CONCEPT, string("Connect_", getinstancename(getid(outobject)), "_", getinstancename(getid(inobject))))
        return new(id, outobject, inobject)
    end
end

getid(x::ConnectTwoObjects) = x.id
geteqid(x::ConnectTwoObjects) = Id(BOUNDARYCONDITION_CONCEPT, string("Eq", getinstancename(getid(x))))

getobjects(x::ConnectTwoObjects) = [x.inobject, x.outobject]
getparent(x::ConnectTwoObjects) = nothing # this framework is not compatible with ConnectTwoObjects

isinitialcondition(::ConnectTwoObjects)  = false # this framework is not compatible with ConnectTwoObjects
isterminalcondition(::ConnectTwoObjects) = false # this framework is not compatible with ConnectTwoObjects

function build!(p::Prob, x::ConnectTwoObjects) # assumes same amount of state variables for both
    N = length(getstatevariables(x.inobject)) 
    addeq!(p, geteqid(x), N)
    return
end

function setconstants!(p::Prob, x::ConnectTwoObjects) # assumes same amount of state variables for both
    outstate = getstatevariables(x.outobject)
    instate = getstatevariables(x.inobject)

    for eq_ix in eachindex(outstate)
        (id_out, ix_out) = getvarout(outstate[eq_ix])
        (id_in, ix_in) = getvarin(instate[eq_ix])
        setconcoeff!(p, geteqid(x), id_out, eq_ix, ix_out,  1.0)
        setconcoeff!(p, geteqid(x),  id_in, eq_ix,  ix_in, -1.0)
    end
    return 
end

update!(::Prob, ::ConnectTwoObjects, ::ProbTime) = nothing

# Assemble - dependent on storage balance to be assembled (wont work if no state-variables, but not really necessary for assembling)
function assemble!(x::ConnectTwoObjects)::Bool
    for obj in getobjects(x)
        isnothing(gethorizon(getbalance(obj))) && return false
    end
    return true
end

# TODO: Decleare interface for cut-style boundary conditions?

# ------- SimpleSingleCuts -------
# (Simple because we don't have any cut selection, and because we allocate and use a fixed number of cuts)

mutable struct SimpleSingleCuts <: BoundaryCondition
    id::Id
    objects::Vector{Any}
    probabilities::Vector{Float64}
    constants::Vector{Float64}
    slopes::Vector{Dict{StateVariableInfo, Float64}}
    maxcuts::Int
    numcuts::Int
    cutix::Int
    lower_bound::Float64

    function SimpleSingleCuts(id::Id, objects::Vector{Any}, probabilities::Vector{Float64}, maxcuts::Int, lower_bound::Float64)
        # sanity checks
        @assert maxcuts > 0
        @assert length(objects) > 0
        for object in objects
            @assert length(getstatevariables(object)) > 0 
        end
        @assert length(probabilities) > 0
        @assert sum(probabilities) ≈ 1.0
        for probability in probabilities
            @assert probability >= 0.0
        end
        
        # allocate internal storage
        constants = Float64[-Inf for __ in 1:maxcuts]
        slopes = Vector{Dict{StateVariableInfo, Float64}}(undef, maxcuts)
        for i in 1:maxcuts
            d = Dict{StateVariableInfo, Float64}()
            for object in objects
                for var in getstatevariables(object)
                    d[var] = 0.0
                end
            end
            slopes[i] = d
        end       

        # set initial counters
        numcuts = 0
        cutix = 0

        return new(id, objects, probabilities, constants, slopes, maxcuts, numcuts, cutix, lower_bound)
    end
end

getid(x::SimpleSingleCuts) = x.id

isinitialcondition(::SimpleSingleCuts)  = false
isterminalcondition(::SimpleSingleCuts) = true

setnumcuts!(x::SimpleSingleCuts, n::Int) = x.numcuts = n
setcutix!(x::SimpleSingleCuts, i::Int) = x.cutix = i

getobjects(x::SimpleSingleCuts) = x.objects
getprobabilities(x::SimpleSingleCuts) = x.probabilities
getconstants(x::SimpleSingleCuts) = x.constants
getslopes(x::SimpleSingleCuts) = x.slopes
getmaxcuts(x::SimpleSingleCuts) = x.maxcuts
getnumcuts(x::SimpleSingleCuts) = x.numcuts
getcutix(x::SimpleSingleCuts) = x.cutix

getparent(::SimpleSingleCuts) = nothing

function getfuturecostvarid(x::SimpleSingleCuts)
    return Id(getconceptname(getid(x)), string(getinstancename(getid(x)), "FutureCost"))
end

function getcutconid(x::SimpleSingleCuts)
    return Id(getconceptname(getid(x)), string(getinstancename(getid(x)), "CutConstraint"))
end

function build!(p::Prob, x::SimpleSingleCuts)
    # add single future cost variable
    addvar!(p, getfuturecostvarid(x), 1)

    # add cut constraints
    addge!(p, getcutconid(x), getmaxcuts(x))

    return
end

# Needed to use setrhsterm! in setconstants!
# TODO: Extend Prob interface to allow setrhs!(prob, conid, value) instead of setrhsterms!
getcutconstantid(::SimpleSingleCuts) = Id("CutConstant", "CutConstant")

function setconstants!(p::Prob, x::SimpleSingleCuts)
    # set future cost variable objective function
    setobjcoeff!(p, getfuturecostvarid(x), 1, 1.0)

    for cutix in 1:getmaxcuts(x)
        # set future cost variable in lhs of cut constraints
        setconcoeff!(p, getcutconid(x), getfuturecostvarid(x), cutix, 1, 1.0)

        # inactivate cut constant
        setrhsterm!(p, getcutconid(x), getcutconstantid(x), cutix, x.lower_bound)

        # inactivate cut slopes
        for object in getobjects(x)
            for statevar in getstatevariables(object)
                (varid, varix) = getvarout(statevar)
                setconcoeff!(p, getcutconid(x), varid, cutix, varix, 0.0)
            end
        end
    end
    return
end

update!(::Prob, ::SimpleSingleCuts, ::ProbTime) = nothing

function _set_values_to_zero!(d::Dict)
    for (k, v) in d
        d[k] = zero(typeof(v))
    end
    return nothing
end

function updatecuts!(p::Prob, x::SimpleSingleCuts, 
                     scenarioparameters::Vector{Tuple{Float64, Dict{StateVariableInfo, Float64}}})
    @assert length(scenarioparameters) == length(x.probabilities)
    
    # update cutix
    cutix = getcutix(x) + 1
    if cutix > getmaxcuts(x)
        cutix = 1
        setcutix!(x, cutix)
    elseif getnumcuts(x) == getmaxcuts(x)
        setcutix!(x, cutix)
    else
        setcutix!(x, cutix)
        setnumcuts!(x, cutix)
    end
    
    # get internal storage for cut parameters
    avgconstants = getconstants(x)
    avgslopes = getslopes(x)

    # calculate average cut parameters
    avgconstant = 0.0
    avgslope = avgslopes[cutix]
    _set_values_to_zero!(avgslope)
    for (i, probability) in enumerate(getprobabilities(x))
        (constant, slopes) = scenarioparameters[i]
        avgconstant += constant * probability
        for (var, value) in slopes
            avgslope[var] += value * probability
        end
    end

    # store updated cut internally
    avgconstants[cutix] = avgconstant
    avgslopes[cutix] = avgslope

    # set the newly updated cut in the problem
    setrhsterm!(p, getcutconid(x), getcutconstantid(x), cutix, avgconstant)
    for (var, slope) in avgslope
        (varid, varix) = getvarout(var)
        setconcoeff!(p, getcutconid(x), varid, cutix, varix, -slope)
    end

    return
end

function clearcuts!(p::Prob, x::SimpleSingleCuts)
    # get internal storage for cut parameters
    avgconstants = getconstants(x)
    avgslopes = getslopes(x)
    
    # inactivate cut parameters in internal storage
    fill!(avgconstants, x.lower_bound)
    for slopes in avgslopes
        _set_values_to_zero!(slopes)
    end

    # set counters to 0
    setnumcuts!(x, 0)
    setcutix!(x, 0)

    # inactivate cuts in problem
    for cutix in eachindex(avgconstants)
        setrhsterm!(p, getcutconid(x), getcutconstantid(x), cutix, avgconstants[cutix])
        for (var, slope) in avgslopes[cutix]
            (varid, varix) = getvarout(var)
            setconcoeff!(p, getcutconid(x), varid, cutix, varix, -slope)
        end
    end
    return
end




