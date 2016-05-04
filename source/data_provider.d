module data_provider;

import gfm.math: vec3f, vec4f;

import vertex_provider: VertexProvider;

struct Id
{
    uint source;
    uint no;
}

struct Data
{
    enum State { New, Updated, Discarded }

    Id id;
    double x, y, z, dx, dy, dz;
    long timestamp;
    State state;
    Id[] associated;
}

struct Point
{
    vec3f xyz;
    long timestamp;
    Data.State state;
}

struct IntermediateData
{
    Id id;
    Point[] point;
}

struct TimestampSlider
{
private
{
    long[] _timestamp;
    long   _idx;
}

    invariant
    {
        assert(_idx >= 0);
        if(_timestamp.length)
            assert(_idx < _timestamp.length);
    }

    this(long[] timestamp)
    {
        assert(timestamp.length);
        _timestamp = timestamp;
    }

    auto current()
    {
        return _timestamp[_idx];
    }

    auto currIndex()
    {
        return _idx;
    }

    auto length()
    {
        return _timestamp.length;
    }

    auto set(ulong value)
    {        
        move(value - current);
    }

    auto setIndex(ulong idx)
    {        
        assert(idx >= 0);
        if(_timestamp.length)
            assert(idx < _timestamp.length);
        _idx = idx;
    }

    auto moveNext()
    {
        if(_idx < _timestamp.length - 1)
            _idx++;
    }

    auto movePrev()
    {
        if(_idx > 0)
            _idx--;
    }

    auto move(long delta)
    {
        long lim = current + delta;

        if(delta > 0)
        {
            while((current() < lim) && (_idx < _timestamp.length - 1))
                moveNext();
        }
        else
        {
            while((current() > lim) && (_idx > 0))
                movePrev(); 
        }
    }
}

unittest
{   
    import std.range: iota;
    import std.array: array;

    auto s = TimestampSlider(1.iota(10L).array);

    assert(s.current == 1);
    s.movePrev();
    assert(s.current == 1);
    s.moveNext();
    assert(s.current == 2);
    s.moveNext();
    assert(s.current == 3);
    s.move(3);
    assert(s.current == 6);
    s.move(2);
    assert(s.current == 8);
    s.move(5);
    assert(s.current == 9);
    s.move(-2);
    assert(s.current == 7);
    s.move(-3);
    assert(s.current == 4);
    s.move(-6);
    assert(s.current == 1);
}

struct DataProvider
{
	// bounding box
	vec3f minimal;
    vec3f maximum;

    // time window
    TimestampSlider timestamp_slider;

    IntermediateData[uint][uint] idata;

    VertexProvider[] vertex_provider;

    Data[] data;

    private static auto intermediateToTarget(ref IntermediateData idt)
    {
    	import std.algorithm: map;
	    import vertex_provider: Vertex;

        auto color = sourceToColor(idt.id.source);
        return idt.point.map!(a => Vertex(
                a.xyz,
                color,
            ));
    }

    private static auto intermediateToTriangle(ref IntermediateData idt)
    {
    	import std.algorithm: map;
        import std.math: sqrt;
	    import vertex_provider: Vertex;

        enum h = 1000.;

        //auto color = sourceToColor(idt.id.source);
        auto color = vec4f(1, 0, 1, 1);
        auto jagged = idt.point.map!(a => [
        	Vertex(
                a.xyz + vec3f(0, -sqrt(2.)*h, 0),
                color,
            ),
            Vertex(
                a.xyz + vec3f(-h/2, sqrt(7./4)*h, 0),
                color,
            ),
            Vertex(
                a.xyz + vec3f(+h/2, sqrt(7./4)*h, 0),
                color,
            ),
            ]);

        Vertex[] flatten;
        foreach(e; jagged)
        	flatten ~= e;

        return flatten;
    }

    this(Data[] data)
    {
    	import std.algorithm: map, sort, uniq;
	    import std.array: array;

    	this.data = data;
    	setTimeWindow(long.min, long.max);

    	long[] times = data.map!("a.timestamp").array.sort().uniq().array;
    	timestamp_slider = TimestampSlider(times);
    }

    public void close()
    {
	    foreach(ref vp; vertex_provider)
	    {
	    	vp.destroy();
	    }
    }

    public void setPointCount(int n)
    {
    	foreach(ref vp; vertex_provider)
    		vp.setPointCount(n);
    }

    public void setTimeWindow(long start, long finish)
	{
		import std.algorithm: filter;
	    import std.array: array, back;
	    import std.math: isNaN;
	    import vertex_provider: Vertex, VertexSlice;

	    minimal = vec3f(float.max, float.max, float.max);
	    maximum = vec3f(float.min_normal, float.min_normal, float.min_normal);

	    auto sdata = data.filter!(a => a.timestamp > start && a.timestamp <= finish);

	    idata = null;

	    foreach(e; sdata)
	    {
	        auto s = idata.get(e.id.source, null);

	        if(s is null)
	        {
	            idata[e.id.source][e.id.no] = IntermediateData(e.id, [Point(vec3f(e.x, e.y, e.z), e.timestamp, e.state)]);
	        }
	        else
	        {
	            if(e.id.no in s)
	            {
	                s[e.id.no].point ~= Point(vec3f(e.x, e.y, e.z), e.timestamp, e.state);
	            }
	            else
	            {
	                idata[e.id.source][e.id.no] = IntermediateData(e.id, [Point(vec3f(e.x, e.y, e.z), e.timestamp, e.state)]);                    
	            }
	        }

	        // finding minimal and maximum values of bounding box
	        if(!e.x.isNaN)
	        {
	        	if(e.x > maximum.x)
	        		maximum.x = e.x;
	        	if(e.x < minimal.x)
	        		minimal.x = e.x;
	        }

	        if(!e.y.isNaN)
	        {
	        	if(e.y > maximum.y)
	        		maximum.y = e.y;
	        	if(e.y < minimal.y)
	        		minimal.y = e.y;
	        }

	        if(!e.z.isNaN)
	        {
	        	if(e.z > maximum.z)
	        		maximum.z = e.z;
	        	if(e.z < minimal.z)
	        		minimal.z = e.z;
	        }
	    }

	    Vertex[] vertices, vertices2;
	    VertexSlice[] slices, slices2;

	    foreach(source; idata)
	    {
	        foreach(no; source)
	        {
	            slices  ~= VertexSlice(VertexSlice.Kind.LineStrip, vertices.length, 0);
	            slices2 ~= VertexSlice(VertexSlice.Kind.Triangles, vertices.length*3, 0);
	            vertices  ~= intermediateToTarget(no).array;
	            vertices2 ~= intermediateToTriangle(no).array;
	            slices.back.length = vertices.length - slices.back.start;
	            slices2.back.length = 3*slices.back.length;
	        }
	    }

	    close();

	    vertex_provider = [
	    	new VertexProvider(vertices2, slices2, minimal, maximum),
	    	new VertexProvider(vertices, slices, minimal, maximum),
	    ];
    }
}

auto sourceToColor(uint source)
{
    auto colors = [
          1:vec4f(1.0, 0.0, 0.0, 1.0), 
          2:vec4f(0.0, 1.0, 0.0, 1.0), 
          3:vec4f(0.0, 0.0, 1.0, 1.0), 
          4:vec4f(1.0, 1.0, 0.5, 1.0), 
          5:vec4f(1.0, 0.5, 0.5, 1.0), 
          6:vec4f(1.0, 1.0, 0.5, 1.0), 
          7:vec4f(1.0, 1.0, 0.5, 1.0), 
          8:vec4f(1.0, 1.0, 0.5, 1.0), 
          9:vec4f(1.0, 1.0, 0.5, 1.0), 
         10:vec4f(1.0, 1.0, 0.5, 1.0), 
         11:vec4f(1.0, 1.0, 0.5, 1.0), 
         12:vec4f(1.0, 1.0, 0.5, 1.0), 
         13:vec4f(1.0, 1.0, 0.5, 1.0), 
         14:vec4f(1.0, 1.0, 0.5, 1.0), 
         15:vec4f(1.0, 1.0, 0.5, 1.0), 
         16:vec4f(1.0, 1.0, 0.5, 1.0), 
         17:vec4f(1.0, 1.0, 0.5, 1.0), 
         29:vec4f(0.6, 0.9, 0.5, 1.0),
         31:vec4f(1.0, 1.0, 0.5, 1.0),
        777:vec4f(0.9, 0.5, 0.6, 1.0),
        999:vec4f(1.0, 1.0, 1.0, 1.0),
     16_834:vec4f(1.0, 1.0, 1.0, 1.0),
    ];

    return colors.get(source, vec4f(1, 0, 1, 1));
}

auto testData()
{
    return [
	   Data(Id( 1, 126), 3135.29,  668.659, 0, 3.80239e-05, 1.31036e-05, 0, 10000000, Data.State.New, []), 
	   Data(Id(12,  89), 2592.73,  29898.1, 0, 3.85585e-05, 1.34142e-05, 0, 20000000, Data.State.New, []), 
	   Data(Id( 1, 126),  4860.4, -85.6403, 0, 3.94945e-05, 1.39192e-05, 0, 110000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 4718.28,  30201.3, 0, 4.04358e-05, 1.41767e-05, 0, 120000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 7485.96, -190.656, 0, 3.49682e-05, 1.20792e-05, 0, 210000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 7217.78,  31579.6, 0, 3.76826e-05, 1.33714e-05, 0, 220000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 9361.67,   2587.7, 0, 3.81475e-05, 1.32941e-05, 0, 310000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 8803.98,  31867.5, 0, 4.10037e-05, 1.51577e-05, 0, 320000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 10817.4,  2053.81, 0, 3.7822e-05, 1.33459e-05, 0, 410000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 10319.9,  32846.7, 0, 3.9981e-05, 1.25012e-05, 0, 420000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 12390.7,  2317.39, 0, 3.51232e-05, 1.211e-05, 0, 510000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 12101.3,  33290.6, 0, 3.80668e-05, 1.33354e-05, 0, 520000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 15186.9,  4456.81, 0, 3.85072e-05, 1.34504e-05, 0, 610000000, Data.State.Updated, []), 
	   Data(Id(12,  89),   15099,    34126, 0, 3.69999e-05, 1.31662e-05, 0, 620000000, Data.State.Updated, []), 
	   Data(Id( 1, 126),   15811,  4352.42, 0, 3.86606e-05, 1.39273e-05, 0, 710000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 15750.3,  34418.7, 0, 3.70218e-05, 1.39425e-05, 0, 720000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 18040.1,  4411.44, 0, 3.73007e-05, 1.30977e-05, 0, 810000000, Data.State.Updated, []), 
	   Data(Id(12,  89),   18450,  35493.3, 0, 3.82323e-05, 1.29743e-05, 0, 820000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 20886.9,  4700.86, 0, 3.61158e-05, 1.25823e-05, 0, 910000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 20338.8,  36117.9, 0, 3.91221e-05, 1.45856e-05, 0, 920000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 22232.5,  6572.29, 0, 3.862e-05, 1.30119e-05, 0, 1010000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 22569.5,    36753, 0, 3.77246e-05, 1.38976e-05, 0, 1020000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 23841.5,     7520, 0, 4.06929e-05, 1.41751e-05, 0, 1110000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 23030.3,  37399.1, 0, 4.13317e-05, 1.44872e-05, 0, 1120000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 25883.6,  8127.31, 0, 3.72253e-05, 1.30543e-05, 0, 1210000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 26894.2,  38076.8, 0, 4.06506e-05, 1.42473e-05, 0, 1220000000, Data.State.Updated, []), 
	   Data(Id( 1, 126),   27827,  9057.05, 0, 3.65453e-05, 1.35521e-05, 0, 1310000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 27829.2,  38624.7, 0, 3.98909e-05, 1.38391e-05, 0, 1320000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 29128.5,  9154.44, 0, 3.8298e-05, 1.07218e-05, 0, 1410000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 30832.9,  39502.2, 0, 3.7483e-05, 1.24697e-05, 0, 1420000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 31602.9,   9282.4, 0, 4.0744e-05, -1.29323e-05, 0, 1510000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 31785.5,  39910.8, 0, 4.18978e-05, -1.38727e-05, 0, 1520000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 33973.6,  8615.77, 0, 4.22235e-05, -1.39142e-05, 0, 1610000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 34543.4,  39246.4, 0, 4.03889e-05, -1.35042e-05, 0, 1620000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 37100.9,  8723.32, 0, 4.30759e-05, -1.34761e-05, 0, 1710000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 36346.9,  38694.4, 0, 4.34238e-05, -1.35342e-05, 0, 1720000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 38716.1,  8272.56, 0, 4.3156e-05, -1.28445e-05, 0, 1810000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 38273.6,    38011, 0, 4.24981e-05, -1.31894e-05, 0, 1820000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 40968.5,  6778.36, 0, 4.28007e-05, -1.37471e-05, 0, 1910000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 39485.8,    37357, 0, 4.18349e-05, -1.40835e-05, 0, 1920000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 41736.1,   6818.2, 0, 4.11653e-05, -1.49535e-05, 0, 2010000000, Data.State.Updated, []), 
	   Data(Id(12,  89),   42242,  36425.5, 0, 4.13311e-05, -1.24453e-05, 0, 2020000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 44605.6,  6152.04, 0, 4.17301e-05, -1.4455e-05, 0, 2110000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 43082.6,  36391.4, 0, 4.13824e-05, -1.40265e-05, 0, 2120000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 46346.3,  5509.49, 0, 4.09459e-05, -1.27778e-05, 0, 2210000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 47068.2,  34976.8, 0, 4.23123e-05, -1.35518e-05, 0, 2220000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 47749.2,  4449.36, 0, 4.24101e-05, -1.30696e-05, 0, 2310000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 48361.4,  34596.8, 0, 3.9334e-05, -1.22637e-05, 0, 2320000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 50347.4,  3547.09, 0, 4.13003e-05, -1.33051e-05, 0, 2410000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 50459.5,  34002.1, 0, 3.85042e-05, -1.36172e-05, 0, 2420000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 52208.5,  2735.65, 0, 4.2023e-05, -1.33102e-05, 0, 2510000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 53024.4,  33244.2, 0, 4.36291e-05, -1.34913e-05, 0, 2520000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 54349.9,  2661.61, 0, 4.04107e-05, -1.26464e-05, 0, 2610000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 54822.9,  32615.2, 0, 4.07053e-05, -1.29543e-05, 0, 2620000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 57004.1,  2121.54, 0, 4.0635e-05, -1.29015e-05, 0, 2710000000, Data.State.Updated, []), 
	   Data(Id(12,  89), 56916.5,    31945, 0, 3.9404e-05, -1.28499e-05, 0, 2720000000, Data.State.Updated, []), 
	   Data(Id( 1, 126), 58742.9,  849.437, 0, 4.19979e-05, -1.31393e-05, 0, 2810000000, Data.State.Discarded, []), 
	   Data(Id(12,  89), 59601.7,  31186.4, 0, 4.11686e-05, -1.29374e-05, 0, 2820000000, Data.State.Discarded, []), 
	   Data(Id(29,   1), 3135.29,  668.659, 0, 3.80239e-05, 1.31036e-05, 0, 10000000, Data.State.New, [Id(1, 126)]), 
	   Data(Id(29,   2), 2592.73,  29898.1, 0, 3.85585e-05, 1.34142e-05, 0, 20000000, Data.State.New, [Id(12, 113)]), 
	   Data(Id(29,   1),  4860.4, -85.6403, 0, 3.94945e-05, 1.39192e-05, 0, 110000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 4718.28,  30201.3, 0, 4.04358e-05, 1.41767e-05, 0, 120000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 7485.96, -190.656, 0, 3.49682e-05, 1.20792e-05, 0, 210000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 7217.78,  31579.6, 0, 3.76826e-05, 1.33714e-05, 0, 220000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 9361.67,   2587.7, 0, 3.81475e-05, 1.32941e-05, 0, 310000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 8803.98,  31867.5, 0, 4.10037e-05, 1.51577e-05, 0, 320000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 10817.4,  2053.81, 0, 3.7822e-05, 1.33459e-05, 0, 410000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 10319.9,  32846.7, 0, 3.9981e-05, 1.25012e-05, 0, 420000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 12390.7,  2317.39, 0, 3.51232e-05, 1.211e-05, 0, 510000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 12101.3,  33290.6, 0, 3.80668e-05, 1.33354e-05, 0, 520000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 15186.9,  4456.81, 0, 3.85072e-05, 1.34504e-05, 0, 610000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2),   15099,    34126, 0, 3.69999e-05, 1.31662e-05, 0, 620000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1),   15811,  4352.42, 0, 3.86606e-05, 1.39273e-05, 0, 710000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 15750.3,  34418.7, 0, 3.70218e-05, 1.39425e-05, 0, 720000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 18040.1,  4411.44, 0, 3.73007e-05, 1.30977e-05, 0, 810000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2),   18450,  35493.3, 0, 3.82323e-05, 1.29743e-05, 0, 820000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 20886.9,  4700.86, 0, 3.61158e-05, 1.25823e-05, 0, 910000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 20338.8,  36117.9, 0, 3.91221e-05, 1.45856e-05, 0, 920000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 22232.5,  6572.29, 0, 3.862e-05, 1.30119e-05, 0, 1010000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 22569.5,    36753, 0, 3.77246e-05, 1.38976e-05, 0, 1020000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 23841.5,     7520, 0, 4.06929e-05, 1.41751e-05, 0, 1110000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 23030.3,  37399.1, 0, 4.13317e-05, 1.44872e-05, 0, 1120000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 25883.6,  8127.31, 0, 3.72253e-05, 1.30543e-05, 0, 1210000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 26894.2,  38076.8, 0, 4.06506e-05, 1.42473e-05, 0, 1220000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1),   27827,  9057.05, 0, 3.65453e-05, 1.35521e-05, 0, 1310000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 27829.2,  38624.7, 0, 3.98909e-05, 1.38391e-05, 0, 1320000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 29128.5,  9154.44, 0, 3.8298e-05, 1.07218e-05, 0, 1410000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 30832.9,  39502.2, 0, 3.7483e-05, 1.24697e-05, 0, 1420000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 31602.9,   9282.4, 0, 4.0744e-05, -1.29323e-05, 0, 1510000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 31785.5,  39910.8, 0, 4.18978e-05, -1.38727e-05, 0, 1520000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 33973.6,  8615.77, 0, 4.22235e-05, -1.39142e-05, 0, 1610000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 34543.4,  39246.4, 0, 4.03889e-05, -1.35042e-05, 0, 1620000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 37100.9,  8723.32, 0, 4.30759e-05, -1.34761e-05, 0, 1710000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 36346.9,  38694.4, 0, 4.34238e-05, -1.35342e-05, 0, 1720000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 38716.1,  8272.56, 0, 4.3156e-05, -1.28445e-05, 0, 1810000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 38273.6,    38011, 0, 4.24981e-05, -1.31894e-05, 0, 1820000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 40968.5,  6778.36, 0, 4.28007e-05, -1.37471e-05, 0, 1910000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 39485.8,    37357, 0, 4.18349e-05, -1.40835e-05, 0, 1920000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 41736.1,   6818.2, 0, 4.11653e-05, -1.49535e-05, 0, 2010000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2),   42242,  36425.5, 0, 4.13311e-05, -1.24453e-05, 0, 2020000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 44605.6,  6152.04, 0, 4.17301e-05, -1.4455e-05, 0, 2110000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 43082.6,  36391.4, 0, 4.13824e-05, -1.40265e-05, 0, 2120000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 46346.3,  5509.49, 0, 4.09459e-05, -1.27778e-05, 0, 2210000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 47068.2,  34976.8, 0, 4.23123e-05, -1.35518e-05, 0, 2220000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 47749.2,  4449.36, 0, 4.24101e-05, -1.30696e-05, 0, 2310000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 48361.4,  34596.8, 0, 3.9334e-05, -1.22637e-05, 0, 2320000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 50347.4,  3547.09, 0, 4.13003e-05, -1.33051e-05, 0, 2410000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 50459.5,  34002.1, 0, 3.85042e-05, -1.36172e-05, 0, 2420000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 52208.5,  2735.65, 0, 4.2023e-05, -1.33102e-05, 0, 2510000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 53024.4,  33244.2, 0, 4.36291e-05, -1.34913e-05, 0, 2520000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 54349.9,  2661.61, 0, 4.04107e-05, -1.26464e-05, 0, 2610000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 54822.9,  32615.2, 0, 4.07053e-05, -1.29543e-05, 0, 2620000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), 57004.1,  2121.54, 0, 4.0635e-05, -1.29015e-05, 0, 2710000000, Data.State.Updated, [Id(1, 126)]), 
	   Data(Id(29,   2), 56916.5,    31945, 0, 3.9404e-05, -1.28499e-05, 0, 2720000000, Data.State.Updated, [Id(12, 113)]), 
	   Data(Id(29,   1), double.nan, double.nan, double.nan, double.nan, double.nan, double.nan, 2810000000, Data.State.Discarded, []), 
	   Data(Id(29,   2), double.nan, double.nan, double.nan, double.nan, double.nan, double.nan, 2820000000, Data.State.Discarded, [])
	];
}
