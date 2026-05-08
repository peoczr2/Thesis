using MIRPLib

mirp = loadMIRP(:LR1_1_DR1_3_VC1_V7a, 60)
output_path = "mirp_inspect.txt"

function is_scalar_like(x)
    x isa Number || x isa AbstractString || x isa Symbol || x isa Bool || x === nothing
end

function safe_repr(x)
    try
        return repr(x)
    catch
        return "<repr failed>"
    end
end

function inspect_value(name, x; depth=0, maxdepth=4, maxitems=8)
    indent = repeat("  ", depth)
    T = typeof(x)

    println(indent, name, " :: ", T)

    if is_scalar_like(x)
        println(indent, "  value = ", safe_repr(x))
        return
    end

    if depth >= maxdepth
        println(indent, "  <max depth reached>")
        return
    end

    if x isa AbstractArray
        println(indent, "  size = ", size(x), ", length = ", length(x))
        shown = 0
        for (i, item) in enumerate(x)
            shown += 1
            if shown > maxitems
                println(indent, "  ... ", length(x) - maxitems, " more items")
                break
            end
            inspect_value("[$i]", item; depth=depth + 1, maxdepth=maxdepth, maxitems=maxitems)
        end
        return
    end

    if x isa Tuple
        println(indent, "  length = ", length(x))
        for (i, item) in enumerate(x)
            if i > maxitems
                println(indent, "  ... ", length(x) - maxitems, " more items")
                break
            end
            inspect_value("[$i]", item; depth=depth + 1, maxdepth=maxdepth, maxitems=maxitems)
        end
        return
    end

    if x isa AbstractDict
        println(indent, "  length = ", length(x))
        shown = 0
        for (k, v) in x
            shown += 1
            if shown > maxitems
                println(indent, "  ... ", length(x) - maxitems, " more entries")
                break
            end
            println(indent, "  key = ", safe_repr(k))
            inspect_value("value", v; depth=depth + 1, maxdepth=maxdepth, maxitems=maxitems)
        end
        return
    end

    fns = fieldnames(T)
    if isempty(fns)
        println(indent, "  show = ", safe_repr(x))
        return
    end

    println(indent, "  fields = ", collect(fns))
    for fn in fns
        val = getfield(x, fn)
        inspect_value(String(fn), val; depth=depth + 1, maxdepth=maxdepth, maxitems=maxitems)
    end
end

open(output_path, "w") do io
    redirect_stdout(io) do
        println("========== TOP LEVEL ==========")
        println("typeof(mirp) = ", typeof(mirp))
        println("summary(mirp) = ", summary(mirp))
        println("fieldnames(typeof(mirp)) = ", collect(fieldnames(typeof(mirp))))
        println()

        println("========== FIELD OVERVIEW ==========")
        for fn in fieldnames(typeof(mirp))
            val = getfield(mirp, fn)
            println(fn, " :: ", typeof(val))
            if is_scalar_like(val)
                println("  value = ", safe_repr(val))
            elseif val isa AbstractArray
                println("  size = ", size(val), ", length = ", length(val))
            elseif val isa AbstractDict
                println("  length = ", length(val))
            else
                println("  summary = ", summary(val))
            end
        end
        println()

        println("========== RECURSIVE INSPECTION ==========")
        inspect_value("mirp", mirp; maxdepth=4, maxitems=8)
        println()

        println("========== FULL DUMP ==========")
        dump(mirp)
    end
end

println("Wrote MIRP inspection output to ", output_path)