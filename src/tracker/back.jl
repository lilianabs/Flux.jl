init_grad(x) = zero(x)
zero_grad!(x) = zero(x)
zero_grad!(x::AbstractArray) = (x .= 0)

scan(c::Call) = foreach(scan, c.args)

function scan(x::Tracked)
  x.isleaf && return
  ref = x.ref += 1
  if ref == 1
    scan(x.f)
    isdefined(x, :grad) && (x.grad = zero_grad!(x.grad))
  else
    isdefined(x, :grad) || (x.grad = init_grad(x.data))
  end
  return
end

function scan(x)
  istracked(x) && scan(tracker(x))
  return
end

function back_(c::Call, Δ)
  Δs = c.func(Δ)
  (Δs isa Tuple && length(Δs) >= length(c.args)) ||
    error("Gradient is not a tuple of length $(length(c.args))")
  foreach((x, Δ) -> istracked(x) && back(x, Δ), c.args, Δs)
end

back_(::Call{Void}, Δ) = nothing

accum!(x, Δ) = x .+ Δ
accum!(x::AbstractArray, Δ) = (x .+= Δ)

function back(x::Tracked, Δ)
  x.isleaf && (x.grad = accum!(x.grad, Δ); return)
  ref = x.ref -= 1
  if isdefined(x, :grad)
    x.grad = accum!(x.grad, Δ)
    ref == 0 && back_(x.f, x.grad)
  else
    ref == 0 && back_(x.f, Δ)
  end
  return
end

back(x, Δ) = back(tracker(x), Δ)
back(x::Void, Δ) = error("Can't backpropagate through `nothing`")

# Interface methods

# TODO: if an error occurs in `back` the refcounts will be broken
# and `back` will silently fail to update.

function back!(x::Tracked, Δ)
  scan(x)
  back(x, Δ)
end

back!(x, Δ) = back!(tracker(x), Δ)