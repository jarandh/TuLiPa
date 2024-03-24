"""
In this file we define a system for testing all methods in the
INCLUDEELEMENT function registry, and to catch missing tests for 
new methods added in the future.

The system has two parts: 
- The function test_all_includeelement_methods, which should
  contain tests for each method for each INCLUDEELEMENT function
  that is defined in TuLiPa.

- The test_is_all_includeelement_methods_covered function, which
  tests that all methods registered as tested in this file
  (using TESTED_INCLUDE_METHODS), actually cover all methods
  stored in the INCLUDEELEMENT registry.

For the system to work well, each INCLUDEELEMENT test function should behave 
a certain way:
- Define one test function for each generic function in INCLUDEELEMENT.

- The test function should test all methods of the function 
  (i.e. different implementations for different types for the 
   "values" argument. E.g. see test_includeVectorTimeIndex! 
   which tests both value::AbstractVector{DateTime} and value::Dict)

- As a convention, name the test function 
  test_[INCLUDEELEMENT function name]
  (e.g. test_includeVectorTimeIndex!)

- The final line of a test function should call the 
  register_tested_methods function to register how many 
  methods the test function tested.
  (e.g. register_tested_methods(includeVectorTimeIndex!, 2))

- Call the test function inside the 
  test_all_includeelement_methods function 

We put all functionality for this test into a module so that we do not 
(inadvertently) overwrite names the global namespace, which could affect other 
tests in when running the runtests.jl script.
"""

module Test_INCLUDEELEMENT_Methods

using TuLiPa, Test, Dates

const TESTED_INCLUDE_METHODS = Tuple{Function, Int}[]

function register_tested_methods(include_func::Function, num_methods::Int)
    if !haskey(INCLUDEELEMENT, include_func)
        error("Unknown INCLUDEELEMENT function $include_func")
    end
    push!(TESTED_INCLUDE_METHODS, (include_func, num_methods))
    return nothing
end

function run_tests()
    test_all_includeelement_methods()
    test_is_all_includeelement_methods_covered()
end

function test_is_all_includeelement_methods_covered()
    ACTUAL_INCLUDE_METHODS = Tuple{Function, Int}[]
    for f in values(INCLUDEELEMENT)
        f === includeVectorTimeIndex! || continue    # TODO: Remove later
        push!(ACTUAL_INCLUDE_METHODS, (f, length(methods(f))))
    end
    
    tested = Set(TESTED_INCLUDE_METHODS)
    actual = Set(ACTUAL_INCLUDE_METHODS)

    untested = setdiff(actual, tested)

    success = true
    if length(untested) > 0
        success = false
        ns = Dict(f => n for (f, n) in tested)
        for (f, n) in untested
            diff = n - get(ns, f, 0)
            s = diff > 1 ? "s" : ""
            println("Missing test$s for $diff method$s for $f")
        end
    end

    @test success
end

function _test_ret_deps_0(ret)
    @test ret isa Tuple{Bool, Any}
    (ok, deps) = ret
    @test ok
    @test deps isa Vector{Id}
    @test length(deps) == 0
end

function test_includeVectorTimeIndex!()
    # tests method when value::AbstractVector{DateTime}
    (TL, LL) = (Dict(), Dict())
    k = ElementKey("doesnotmatter", "doesnotmatter", "doesnotmatter")
    # empty vector
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, DateTime[])
    # not sorted
    v = [DateTime(2024, 3, 23), DateTime(1985, 7, 1)]
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, v)
    # should be ok
    v = [DateTime(1985, 7, 1)]
    ret = includeVectorTimeIndex!(TL, LL, k, [DateTime(1985, 7, 1)])
    _test_ret_deps_0(ret)
    # same id already stored in lowlevel
    LL[Id(k.conceptname, k.instancename)] = 1
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, [DateTime(1985, 7, 1)])

    # tests method when value::Dict
    (TL, LL) = (Dict(), Dict())
    # missing vector in dict
    @test_throws ErrorException includeVectorTimeIndex!(TL, LL, k, Dict())
    # should be ok
    d = Dict()
    d["Vector"] = v
    ret = includeVectorTimeIndex!(TL, LL, k, d)
    _test_ret_deps_0(ret)

    register_tested_methods(includeVectorTimeIndex!, 2)
end



function includeRangeTimeIndex!(::Dict, lowlevel::Dict, elkey::ElementKey, value::Dict)
    checkkey(lowlevel, elkey)

    deps = Id[]
    
    start  = getdictvalue(value, "Start", DateTime, elkey)
    steps  = getdictvalue(value, "Steps", Int,      elkey) 
    delta  = getdictvalue(value, "Delta", Union{Period, String},   elkey)

    if delta isa String 
        deltakey = Id(TIMEDELTA_CONCEPT, delta)
        push!(deps, deltakey)
        haskey(lowlevel, deltakey) || return (false, deps)
        delta = getduration(lowlevel[deltakey])
    end
    
    delta = Millisecond(delta)
    
    steps > 0              || error(             "Steps <= 0 for $elkey")
    delta > Millisecond(0) || error("Delta <= Millisecond(0) for $elkey")
    
    lowlevel[getobjkey(elkey)] = StepRange(start, delta, start + delta * (steps-1))

    return (true, deps)
end

function includeRangeTimeIndex!(::Dict, lowlevel::Dict, elkey::ElementKey, value::StepRange{DateTime, Millisecond})
    checkkey(lowlevel, elkey)
    deps = Id[]
    value.step > Millisecond(0) || error("Delta <= Millisecond(0) for $elkey")
    lowlevel[getobjkey(elkey)] = value
    return (true, deps)
end

function test_includeRangeTimeIndex!()
    # tests method when value::Dict
    (TL, LL) = (Dict(), Dict())
    k = ElementKey("doesnotmatter", "doesnotmatter", "doesnotmatter")
    # empty dict
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, Dict())
    # wrong type Start
    d = Dict("Start" => "DateTime(1985, 7, 1)", 
             "Steps" => 10,
             "Delta" => Dates.Hour(1)) 
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # wrong type Steps
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => "10",
             "Delta" => Dates.Hour(1)) 
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # wrong type Delta
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => 10,
             "Delta" => 10) 
    @test_throws ErrorException includeRangeTimeIndex!(TL, LL, k, d)
    # should be ok
    d = Dict("Start" => DateTime(1985, 7, 1), 
             "Steps" => 10,
             "Delta" => Dates.Hour(1)) 
    ret = includeRangeTimeIndex!(TL, LL, k, d)
    _test_ret_deps_0(ret)

    register_tested_methods(includeRangeTimeIndex!, 2)
end

end # end module

import .Test_INCLUDEELEMENT_Methods

Test_INCLUDEELEMENT_Methods.run_tests()
