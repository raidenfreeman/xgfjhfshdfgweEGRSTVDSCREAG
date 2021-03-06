#unum-unum.jl


#contains information about the unum type and helper functions directly related to constructor.

#the unum type is an abstract type.  We'll be overloading the call function later
#so we can do "pseudo-constructions" on this type.
doc"""
`Unum{ESS,FSS}` creates a Unum with esizesize ESS and fsizesize FSS.

NB:  Internally this may cast to a different Unum type (UnumLarge or UnumSmall)
for performance purposes.  The `Unum{ESS,FSS}(...)` constructor is always safe
and purposes where computational performance is an issue, use of the internal
types is recommended.
"""
abstract Unum{ESS, FSS} <: Real
export Unum

#general parameter checking for unums.
function __general_unum_check(ESS, FSS, exponent::UInt64, esize::UInt16, fsize::UInt16)
  (ESS > 6) && throw(ArgumentError("ESS == $ESS > 6 disallowed in current implementation"))
  (FSS > 11) && throw(ArgumentError("FSS == $FSS > 11 disallowed in current implementation"))
  _mfs = max_fsize(FSS)
  (fsize > _mfs) && throw(ArgumentError("fsize == $fsize > $_mfs maximum for FSS == $FSS."))
  _mes = max_esize(ESS)
  (esize > _mes) && throw(ArgumentError("esize == $esize > $_mes maximum for ESS == $ESS."))
  _mbe = max_biased_exponent(esize)
  (exponent > _mbe) && throw(ArgumentError("exponent == $exponent > $_mbe maximum for esize == $esize."))
  nothing
end

doc"""
`Unums.UnumSmall{ESS,FSS}` is the internal type for Unums with FSS < 7.  These
numbers require a single unsigned 64-bit integer to store their fractions.
"""
@dev_check type UnumSmall{ESS, FSS} <: Unum{ESS, FSS}
  exponent::UInt64
  fraction::UInt64
  flags::UInt16
  esize::UInt16
  fsize::UInt16
end

#parameter checking.  The call to this check is autogenerated by the @dev_check macro
function __check_UnumSmall(ESS, FSS, exponent::UInt64, fraction::UInt64, flags::UInt16, esize::UInt16, fsize::UInt16)
  (FSS > 6) && throw(ArgumentError("UnumSmall internal class is inappropriate for FSS == $FSS > 6."))
  __general_unum_check(ESS, FSS, exponent, esize, fsize)
  nothing
end

doc"""
`Unums.UnumLarge{ESS,FSS}` is the internal type for Unums with FSS > 6.  These
numbers require an array of 64-bit integers to store their fractions.
"""
@dev_check type UnumLarge{ESS, FSS} <: Unum{ESS, FSS}
  exponent::UInt64
  fraction::ArrayNum{FSS}
  flags::UInt16
  esize::UInt16
  fsize::UInt16
end

#parameter checking.  The call to this check is autogenerated by the @dev_check macro
function __check_UnumLarge{FSS}(_ESS, _FSS, exponent::UInt64, fraction::ArrayNum{FSS}, flags::UInt16, esize::UInt16, fsize::UInt16)
  _FSS != FSS && throw(ArgumentError("ArrayNum FSS must match Unum FSS"))
  (FSS < 7) && throw(ArgumentError("UnumLarge internal class is inappropriate for FSS == $FSS < 7."))
  __general_unum_check(_ESS, _FSS, exponent, esize, fsize)
  nothing
end

#universal copy constructors
UnumSmall{ESS,FSS}(x::UnumSmall{ESS,FSS}) = UnumSmall{ESS,FSS}(x.exponent, x.fraction, x.flags, x.esize, x.fsize)
UnumLarge{ESS,FSS}(x::UnumLarge{ESS,FSS}) = UnumLarge{ESS,FSS}(x.exponent, copy(x.fraction), x.flags, x.esize, x.fsize)
#overide call to provide copy constructors that look like Unum{ESS,FSS} instead of UnumSmall or UnumLarge
@universal function (::Type{Unum{ESS,FSS}})(x::Unum)
  (FSS < 7) ? (UnumSmall(x)) : (UnumLarge(x))
end
@universal function Base.copy(x::Unum)
  (FSS < 7) ? (UnumSmall(x)) : (UnumLarge(x))
end

#override call to allow direct instantiation using the Unum{ESS,FSS} pseudo-constructor.
#The Unum{ESS,FSS} constructor also does trim operation that sets the ubit correctly.
@generated function (::Type{Unum{ESS,FSS}}){ESS,FSS}(exponent::UInt64, fraction, flags::UInt16, esize::UInt16, fsize::UInt16)
  arrayconversion = :(fraction)
  if (fraction == UInt64)
    utype = UnumSmall
  elseif (fraction == Array{UInt64, 1})
    utype = UnumLarge
    arrayconversion = :(ArrayNum{FSS}(fraction))
  elseif (fraction == ArrayNum{FSS})
    utype = UnumLarge
  else
    throw(ArgumentError("fraction must be UInt64, ArrayNum, or Array{UInt64,1} "))
  end

  quote
     #mask out values outside of the flag range.
     flags &= UNUM_FLAG_MASK
     x = $utype{ESS,FSS}(exponent, $arrayconversion, flags, esize, fsize)
     trim_and_set_ubit!(x, fsize)
     x
  end
end

doc"""
  `unum(Unum{ESS,FSS}, exponent, fraction, esize, fsize, flags)` is a guaranteed-safe
  constructor for unums.  Use this if you don't trust your incoming data.  You can
  also use the easy constructor `unum(Unum{ESS,FSS}, exponent, fraction, flags)`
  passing a signed integer exponent, which automatically creates the size parameters
  in a safe fashion.  `unum(x::Unum{ESS,FSS})`, unlike the equivalent `Unum{ESS,FSS}`
  constructor forms, is a safe copy constructor.
"""
function unum{ESS,FSS}(::Type{Unum{ESS,FSS}}, exponent::UInt64, fraction, flags::UInt16, esize::UInt16, fsize::UInt16)
  if !options[:devmode]
    __general_unum_check(ESS, FSS, exponent, esize, fsize)
    (FSS > 6) && __check_ArrayNum(FSS, fraction)
  end
  Unum{ESS,FSS}(exponent, fraction, flags, esize, fsize)
end
function unum{ESS,FSS}(::Type{Unum{ESS,FSS}}, exponent::Int64, fraction, flags::UInt16)
  (esize, exp) = encode_exp(exponent)
  fsize = __minimum_data_width(fraction)
  unum(Unum{ESS,FSS}, exp, fraction, flags, esize, fsize)
end
@universal function unum(x::Unum)
  __general_unum_check(ESS, FSS, x.exponent, x.esize, x.fsize)
  (FSS > 6) && __check_ArrayNum(x.fraction)
  (FSS < 7) ? UnumSmall{ESS,FSS}(x.exponent, x.fraction, x.flags, x.esize, x.fsize) : UnumLarge{ESS,FSS}(x.exponent, x.fraction, x.flags, x.esize, x.fsize)
end

doc"""
  `Unums.buildunum(::Type{[UnumLarge|UnumSmall]}, exponent::Int64, fraction, flags, fsize)` builds a
  unum out of the respective components.  `buildunum` is intended for internal
  use and instead of throwing errors when the values are outside of the standard
  ranges, it will create constants mmr/sss.
"""
@universal function buildunum(T::Type{Unum}, true_exponent::Int64, fraction, flags::UInt16, fsize::UInt16)

  #determine properties of the destination type.
  min_exp_subnormal = min_exponent(ESS, FSS)
  min_exp_normal = min_exponent(ESS)
  max_exp = max_exponent(ESS)
  mfsize = max_fsize(FSS)

  #eject easy candidates.
  (true_exponent < min_exp_subnormal) && return sss(U, flags & UNUM_SIGN_MASK)
  (true_exponent > max_exp) && return mmr(U, flags & UNUM_SIGN_MASK)

  #check if we need to make this a subnormal number.
  if (true_exponent < min_exp_normal)
    #figure the needed difference.
    shiftvalue = to16(min_exp_normal - true_exponent)
    #load the values into a holding unum.
    result = U(z64, fraction, flags, max_esize(ESS), min(fsize, mfsize))
    rsh_and_set_ubit!(result, shiftvalue)
    frac_set_bit!(result, shiftvalue)
  else
    shiftvalue = z16
    (esize, exponent) = encode_exp(true_exponent)
    result = U(exponent, fraction, flags, esize, min(fsize, mfsize))
  end

  trim_and_set_ubit!(result, min(fsize + shiftvalue, mfsize))
  exact_trim!(result)
  result
end


export unum

#a blank constructor uses the default environment setting
function (::Type{Unum})(args...)
  environment()(args...)
end

#masks for the unum flags variable.
const UNUM_SIGN_MASK = UInt16(0x0002)
const UNUM_UBIT_MASK = UInt16(0x0001)
const UNUM_FLAG_MASK = UInt16(0x0003)
