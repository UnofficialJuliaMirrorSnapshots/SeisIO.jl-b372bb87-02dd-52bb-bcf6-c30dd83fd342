# export FDSNevq, FDSNevt, FDSNsta
export FDSNsta

# =============================================================================
# No export

function fdsn_chp(chans::Union{String,Array{String,1},Array{String,2}}; v::Int64 = KW.v)
  # Parse channel config
  if isa(chans, String)
    C = parse_chstr(chans, fdsn = true)
  elseif isa(chans, Array{String,1})
    C = parse_charr(chans, fdsn = true)
  else
    C = copy(chans)
  end
  minreq!(C)
  v > 1 && println(stdout, "Most compact request form = ", C)
  return C
end

"""
    S = FDSNsta(chans, KW)

Retrieve station/channel info for formatted parameter file (or string) `chans`
into an empty SeisData structure.

Standard keywords: rad, reg, src, to, v

Other keywords:
* msr: get MultiStage (full) responses?
* s: Start time
* t: Termination (end) time
* xf: Name of XML file to save station metadata

See also: chanspec, parsetimewin, get_data!, SeisIO.KW
"""
function FDSNsta(chans="*"::Union{String,Array{String,1},Array{String,2}};
                  msr ::Bool              = false,          # MultiStageResp
                  rad ::Array{Float64,1}  = KW.rad,         # Search radius
                  reg ::Array{Float64,1}  = KW.reg,         # Search region
                  s   ::TimeSpec          = 0,              # Start
                  src ::String            = KW.src,         # Source server
                  t   ::TimeSpec          = (-600),         # End or Length (s)
                  to  ::Int               = KW.to,          # Read timeout (s)
                  v   ::Int64             = KW.v,           # Verbosity
                  xf  ::String            = "FDSNsta.xml"   # XML filename
                 )

  d0, d1 = parsetimewin(s, t)
  v > 0 && @info(tnote("Querying FDSN stations"))
  URL = string(fdsn_uhead(src), "station/1/query")
  BODY = "level=response\nformat=xml\n"
  wc = "*"

  # Add geographic search to BODY
  if !isempty(rad)
    BODY *= string( "latitude=", rad[1], "\n",
                    "longitude=", rad[2], "\n",
                    "minradius=", rad[3], "\n",
                    "maxradius=", rad[4], "\n")
  end
  if !isempty(reg)
    BODY *= string( "minlatitude=", reg[1], "\n",
                    "maxlatitude=", reg[2], "\n",
                    "minlongitude=", reg[3], "\n",
                    "maxlongitude=", reg[4], "\n" )
  end

  # Add channel search to BODY
  if chans == wc
    (isempty(reg) && isempty(rad)) && error("No query! Please specify a search radius, a rectangular search region, or some channels.")
    BODY *= string("* * * * ", d0, " ", d1, "\n")
  else
    C = fdsn_chp(chans, v=v)
    Nc = size(C,1)
    for i = 1:Nc
      str = ""
      for j = 1:4
        str *= (" " * (isempty(C[i,j]) ? wc : C[i,j]))
      end
      BODY *= string(str, " ", d0, " ", d1, "\n")
    end
  end
  if v > 1
    printstyled("request url:", color=:light_green)
    println(URL)
    printstyled("request body: \n", color=:light_green)
    println(BODY)
  end
  open(xf, "w") do io
    request("POST", URL, webhdr, BODY, response_stream=io)
  end

  # Build channel list
  v > 0 && @info(tnote("Building list of channels"))
  io = open(xf, "r")
  xsta = read(io, String)
  close(io)
  S = FDSN_sta_xml(xsta, msr=msr, v=v)
  return S
end

function FDSNget!(U::SeisData, chans::Union{String,Array{String,1},Array{String,2}};
  autoname  ::Bool              = false,          # Auto-generate file names?
  fmt       ::String            = KW.fmt,         # Request format
  msr       ::Bool              = false,          # MultiStageResp
  nd        ::Real              = KW.nd,          # Number of days per request
  opts      ::String            = KW.opts,        # User-defined options
  rad       ::Array{Float64,1}  = KW.rad,         # Search radius
  reg       ::Array{Float64,1}  = KW.reg,         # Search region
  s         ::TimeSpec          = 0,              # Start
  si        ::Bool              = KW.si,          # Station info?
  src       ::String            = KW.src,         # Source server
  t         ::TimeSpec          = (-600),         # End or Length (s)
  to        ::Int64             = KW.to,          # Read timeout (s)
  v         ::Int64             = KW.v,           # Verbosity
  w         ::Bool              = KW.w,           # Write to disk?
  xf        ::String            = "FDSNsta.xml",  # XML filename
  y         ::Bool              = KW.y            # Sync?
  )

  parse_err = false
  n_badreq = 0
  wc = "*"
  d0, d1 = parsetimewin(s, t)

  # (1) Time-space query for station info
  if si
    S = FDSNsta(chans,
                msr   = msr,
                rad   = rad,
                reg   = reg,
                s     = d0,
                src   = src,
                t     = d1,
                to    = to,
                v     = v,
                xf    = xf
                )
  end

  # (1a) Can we autoname the file? True iff S.n == 1
  (S.n == 1) || (autoname = false)

  # (2) Build ID strings for data query
  ID_str = Array{String,1}(undef,S.n)
  for i = 1:S.n
    ID_mat = split(S.id[i], ".")
    ID_mat[isempty.(ID_mat)] .= wc
    ID_str[i] = join(ID_mat, " ")
  end
  if v > 1
    printstyled("data query strings:\n", color=:light_green)
    for i = 1:length(ID_str)
      println(stdout, ID_str[i])
    end
  end

  # (3) Data query
  v > 0 && @info(tnote("Data query begins"))
  URL = string(fdsn_uhead(src), "dataselect/1/query")
  if occursin("ncedc", URL) || occursin("scedc", URL)
    BODY = ""
    if fmt != "miniseed"
      @warn(string("format ", fmt, " ignored; server only allows miniseed."))
    end
  else
    BODY = "format=" * fmt * "\n"
    if !isempty(opts)
      OPTS = split(opts, "&")
      for opt in OPTS
        BODY *= string(opt, "\n")
      end
    end
  end

  # Set the data source
  for i = 1:S.n
    S.src[i] = URL
  end

  # Create variables for query
  ts = tstr2int(d0)
  ti = round(Int64, nd*86400000000)
  te = tstr2int(d1)
  t1 = deepcopy(ts)
  rn = 0
  while t1 < te
    rn += 1
    os = rn > 1 ? 1 : 0
    t1 = min(ts + ti, te)
    s_str = int2tstr(ts + os)
    t_str = int2tstr(t1)
    qtail = string(" ", s_str, " ", t_str, "\n")
    QUERY = identity(BODY)
    for i = 1:S.n
      QUERY *= ID_str[i]*qtail
    end
    if v > 1
      printstyled(string("request url: ", URL, "\n"), color=:light_green)
      printstyled(string("request body: \n", QUERY), color=:light_green)
    end

    # Request via "POST"
    if w
      if fmt == "miniseed"
        ext = "mseed"
      else
        ext = fmt
      end

      # Generate filename
      yy = s_str[1:4]
      mm = s_str[6:7]
      dd = s_str[9:10]
      HH = s_str[12:13]
      MM = s_str[15:16]
      SS = s_str[18:19]
      nn = lpad(div(parse(Int64, s_str[21:26]), 1000), 3, '0')
      jj = lpad(md2j(yy, mm, dd), 3, '0')
      if autoname
        fname = join([yy, jj, HH, MM, SS, nn, S.id[1], "R", ext], '.')
      else
        fname = join([yy, jj, HH, MM, SS, nn, "FDSNWS", src, ext], '.')
      end
      safe_isfile(fname) && @warn(string("File ", fname, " contains an identical request; overwriting."))
      open(fname, "w") do io
        request("POST", URL, webhdr, QUERY, readtimeout=to, response_stream=io)
      end
      io = open(fname, "r")
      parsable = true
    else
      (R, parsable) = get_http_post(URL, QUERY, to)
      io = IOBuffer(R)
    end

    # Parse data (if we can)
    if parsable
      if fmt == "mseed" || fmt == "miniseed"
        parsemseed!(S, io, v, KW.nx_add, KW.nx_add)
      elseif fmt == "geocsv" || fmt == "geocsv.tspair"
        read_geocsv_tspair!(S, io)
      elseif fmt == "geocsv.slist"
        read_geocsv_slist!(S, io)
      else
        parse_err = true
        n_badreq += 1
        S += SeisChannel(id = string("...YYY", n_badreq),
                         misc = Dict{String,Any}( "url" => URL,
                                                  "body" => QUERY,
                                                  "data" => read(io) ) )
      end
    else
      # Should only happen with an error message (parsable to String) in io
      parse_err = true
      n_badreq += 1
      S += SeisChannel(id = string("XX...", n_badreq),
                       misc = Dict{String,Any}( "url" => URL,
                                                "body" => QUERY,
                                                "data" => readlines(io) ) )
    end
    close(io)
    ts += ti
  end

  append!(U,S)
  # Done!
  v > 0 && @info(tnote("Done FDSNget query."))
  return parse_err
end
