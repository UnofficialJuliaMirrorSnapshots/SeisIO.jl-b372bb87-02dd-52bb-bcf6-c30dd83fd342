export SeisData

# This is type-stable for S = SeisData() but not for keyword args
@doc """
    SeisData

A custom structure designed to contain the minimum necessary information for
processing univariate geophysical data.

    SeisChannel

A single channel designed to contain the minimum necessary information for
processing univariate geophysical data.

    SeisHdr

A container for earthquake source information; specific to seismology.

    SeisEvent

A structure for discrete seismic events, comprising a SeisHdr for the event
  descriptor and a SeisData for data.

## Fields: SeisData, SeisChannel

| **Field** | **Description** |
|:-------|:------ |
| :n     | Number of channels [^1] |
| :c     | TCP connections feeding data to this object [^1] |
| :id    | Channel ids. use NET.STA.LOC.CHAN format when possible  |
| :name  | Freeform channel names |
| :loc   | Location (position) vector; any subtype of InstrumentPosition  |
| :fs    | Sampling frequency in Hz; set to 0.0 for irregularly-sampled data. |
| :gain  | Scalar gain; divide data by the gain to convert to units  |
| :resp  | Instrument response; any subtype of InstrumentResponse |
| :units | String describing data units. UCUM standards are assumed. |
| :src   | Freeform string describing data source. |
| :misc  | Dictionary for non-critical information. |
| :notes | Timestamped notes; includes automatically-logged acquisition and |
|        | processing information. |
| :t     | Matrix of time gaps, formatted [Sample# GapLength] |
|        | gaps are in μs measured from the Unix epoch |
| :x     | Data |

[^1]: Not present in SeisChannel objects.

See documentation (https://seisio.readthedocs.io/) for more details.
""" SeisData
mutable struct SeisData <: GphysData
  n::Int64
  id::Array{String,1}                 # id
  name::Array{String,1}               # name
  loc::Array{InstrumentPosition,1}    # loc
  fs::Array{Float64,1}                # fs
  gain::Array{Float64,1}              # gain
  resp::Array{InstrumentResponse,1}   # resp
  units::Array{String,1}              # units
  src::Array{String,1}                # src
  misc::Array{Dict{String,Any},1}     # misc
  notes::Array{Array{String,1},1}     # notes
  t::Array{Array{Int64,2},1}          # time
  x::Array{FloatArray,1}              # data
  c::Array{TCPSocket,1}               # connections

  function SeisData()
    return new(0,
                Array{String,1}(undef,0),
                Array{String,1}(undef,0),
                Array{InstrumentPosition,1}(undef,0),
                Array{Float64,1}(undef,0),
                Array{Float64,1}(undef,0),
                Array{InstrumentResponse,1}(undef,0),
                Array{String,1}(undef,0),
                Array{String,1}(undef,0),
                Array{Dict{String,Any},1}(undef,0),
                Array{Array{String,1},1}(undef,0),
                Array{Array{Int64,2},1}(undef,0),
                Array{FloatArray,1}(undef,0),
                Array{TCPSocket,1}(undef,0)
              )
  end

  function SeisData( n::Int64,
            id::Array{String,1}                 , # id
            name::Array{String,1}               , # name
            loc::Array{InstrumentPosition,1}    , # loc
            fs::Array{Float64,1}                , # fs
            gain::Array{Float64,1}              , # gain
            resp::Array{InstrumentResponse,1}   , # resp
            units::Array{String,1}              , # units
            src::Array{String,1}                , # src
            misc::Array{Dict{String,Any},1}     , # misc
            notes::Array{Array{String,1},1}     , # notes
            t::Array{Array{Int64,2},1}          , # time
            x::Array{FloatArray,1})

    return new(n,
      id, name, loc, fs, gain, resp, units, src, misc, notes, t, x,
      Array{TCPSocket,1}(undef,0)
      )
  end

  function SeisData(n::UInt)
    S = new(n,
                Array{String,1}(undef,n),
                Array{String,1}(undef,n),
                Array{InstrumentPosition,1}(undef,n),
                Array{Float64,1}(undef,n),
                Array{Float64,1}(undef,n),
                Array{InstrumentResponse,1}(undef,n),
                Array{String,1}(undef,n),
                Array{String,1}(undef,n),
                Array{Dict{String,Any},1}(undef,n),
                Array{Array{String,1},1}(undef,n),
                Array{Array{Int64,2},1}(undef,n),
                Array{FloatArray,1}(undef,n),
                Array{TCPSocket,1}(undef,0)
              )

    # Fill these fields with something to prevent undefined reference errors
    fill!(S.id, "")                                         #  id
    fill!(S.name, "")                                       # name
    fill!(S.src, "")                                        # src
    fill!(S.units, "")                                      # units
    fill!(S.fs, 0.0)                                        # fs
    fill!(S.gain, 1.0)                                      # gain
    for i = 1:n
      S.notes[i]  = Array{String,1}(undef,0)                # notes
      S.misc[i]   = Dict{String,Any}()                      # misc
      S.t[i]      = Array{Int64,2}(undef,0,2)               # t
      S.x[i]      = Array{Float32,1}(undef,0)               # x
      S.loc[i]    = GeoLoc()                                # loc
      S.resp[i]   = PZResp()                                # resp
    end
    return S
  end
  SeisData(n::Int) = n > 0 ? SeisData(UInt(n)) : SeisData()
end

# This intentionally undercounts exotic objects in :misc (e.g. a nested Dict)
# because those objects aren't written to disk or created by SeisIO
function sizeof(S::SeisData)
  s = sizeof(S.c) + 120
  for f in datafields
    V = getfield(S,f)
    s += sizeof(V)
    for i = 1:S.n
      v = getindex(V, i)
      s += sizeof(v)
      if f == :notes
        if !isempty(v)
          s += sum([sizeof(j) for j in v])
        end
      elseif f == :misc
        k = collect(keys(v))
        s += sizeof(k) + 64 + sum([sizeof(j) for j in k])
        for p in values(v)
          s += sizeof(p)
          if typeof(p) == Array{String,1}
            s += sum([sizeof(j) for j in p])
          end
        end
      end
    end
  end
  return s
end

function read(io::IO, ::Type{SeisData})
  Z = getfield(BUF, :buf)
  L = getfield(BUF, :int64_buf)

  # read begins ------------------------------------------------------
  N     = read(io, Int64)
  checkbuf_strict!(L, 2*N)
  readbytes!(io, Z, 3*N)
  c1    = copy(Z[1:N])
  c2    = copy(Z[N+1:2*N])
  y     = code2typ.(getindex(Z, 2*N+1:3*N))
  cmp   = read(io, Bool)
  read!(io, L)
  nx    = getindex(L, N+1:2*N)

  if cmp
    checkbuf_8!(Z, maximum(nx))
  end

  return SeisData(N,
    read_string_vec(io, Z),
    read_string_vec(io, Z),
    InstrumentPosition[read(io, code2loctyp(getindex(c1, i))) for i = 1:N],
    read!(io, Array{Float64, 1}(undef, N)),
    read!(io, Array{Float64, 1}(undef, N)),
    InstrumentResponse[read(io, code2resptyp(getindex(c2, i))) for i = 1:N],
    read_string_vec(io, Z),
    read_string_vec(io, Z),
    [read_misc(io, Z) for i = 1:N],
    [read_string_vec(io, Z) for i = 1:N],
    [read!(io, Array{Int64, 2}(undef, getindex(L, i), 2)) for i = 1:N],
    FloatArray[cmp ?
      Blosc.decompress(getindex(y,i), readbytes!(io, Z, getindex(nx, i))) :
      read!(io, Array{getindex(y,i), 1}(undef, getindex(nx, i)))
      for i = 1:N])
end

function write(io::IO, S::SeisData)
  N     = getfield(S, :n)
  LOC   = getfield(S, :loc)
  RESP  = getfield(S, :resp)
  T     = getfield(S, :t)
  X     = getfield(S, :x)
  MISC  = getfield(S, :misc)
  NOTES = getfield(S, :notes)

  cmp = false
  if KW.comp != 0x00
    nx_max = maximum([sizeof(getindex(X, i)) for i = 1:S.n])
    if (nx_max > KW.n_zip) || (KW.comp == 0x02)
      cmp = true
      Z = getfield(BUF, :buf)
      checkbuf_8!(Z, nx_max)
    end
  end

  codes = Array{UInt8,1}(undef, 3*N)
  L = Array{Int64,1}(undef, 2*N)

  # write begins ------------------------------------------------------
  write(io, N)
  p = position(io)
  skip(io, 19*N+1)

  write_string_vec(io, S.id)                                          # id
  write_string_vec(io, S.name)                                        # name
  i = 0                                                               # loc
  while i < N
    i = i + 1
    loc = getindex(LOC, i)
    setindex!(codes, loctyp2code(loc), i)
    write(io, loc)
  end
  write(io, S.fs)                                                     # fs
  write(io, S.gain)                                                   # gain
  i = 0                                                               # resp
  while i < N
    i = i + 1
    resp = getindex(RESP, i)
    setindex!(codes, resptyp2code(resp), N+i)
    write(io, resp)
  end
  write_string_vec(io, S.units)                                       # units
  write_string_vec(io, S.src)                                         # src

  for i = 1:N; write_misc(io, getindex(MISC, i)); end                 # misc
  for i = 1:N; write_string_vec(io, getindex(NOTES, i)); end          # notes
  i = 0                                                               # t
  while i < N
    i = i + 1
    t = getindex(T, i)
    setindex!(L, size(t,1), i)
    write(io, t)
  end
  i = 0                                                               # x
  while i < N
    i = i + 1
    x = getindex(X, i)
    nx = lastindex(x)
    if cmp
      while l == zero(Int64)
        l = Blosc.compress!(Z, x, level=5)
        (l > zero(Int64)) && break
        nx_max = nextpow(2, nx_max)
        @warn(string("Compression ratio > 1.0 for channel ", i, "; are data OK?"))
      end
      xc = view(Z, 1:l)
      write(io, xc)
      setindex!(L, l, N+i)
    else
      write(io, x)
      setindex!(L, nx, N+i)
    end
    setindex!(codes, typ2code(eltype(x)), 2*N+i)
  end
  q = position(io)

  seek(io, p)
  write(io, codes)
  write(io, cmp)
  write(io, L)
  seek(io, q)
  # write ends ------------------------------------------------------
  return nothing
end
