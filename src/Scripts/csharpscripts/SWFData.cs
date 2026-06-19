using Godot;
using System;
using System.Collections.Generic;


public class Edge
{
	public Vector2 Start;
	public Vector2? Control;
	public Vector2 End;
	public int? FillIndex;

	public Edge() { }
	public Edge(Vector2 start, Vector2? control, Vector2 end, int? fillIndex)
	{
		Start = start; Control = control; End = end; FillIndex = fillIndex;
	}
	public Edge Reversed() => new Edge(End, Control, Start, FillIndex);
}

public class ExportDocument
{
	public Dictionary<int, ShapeData> Shapes = new();
	public Dictionary<int, SpriteExportData> Sprites = new();
}

public class SpriteExportData
{
	public List<ChildInfo> Children = new();
	public List<Dictionary<int, FrameTag>> Frames = new();
	public List<string> FrameNames = new();
	public float LocalX, LocalY;
	public int MaxNestingDepth = 0;
	public Dictionary<int, FrameTag> FirstFrameData = new();
	public string SpriteName = "";
}

public class ChildInfo
{
	public int ID;
	public string Type = "Shape";
	public int Depth;
}

public class ShapeData
{
	public List<SubPath> SubPaths = new();
	public List<StrokePath> Strokes = new();
	public string Svg = "";
}

public class SubPath
{
	public Color FillColor = new(1, 1, 1, 1);
	public List<PathSegment> Segments = new();
	public Vector2 LastPoint;
	public GradientInfo Gradient = null;
	public int GradientId = -1;
}

public class StrokePath
{
	public Color StrokeColor;
	public float Width;
	public List<PathSegment> Segments = new();
}

public class GradientInfo
{
	public float X1, Y1, X2, Y2;
	public List<GradientStop> Stops;
}

public class GradientStop
{
	public Color Color;
	public float Offset;
}

public class PathSegment
{
	public string Type = "line";
	public Vector2 Start, Control, End;
	public Color Color = new(1, 1, 1, 1);
}

public class FrameTag
{
	public int SymbolID, Depth;
	public float X, Y, ScaleX = 1, ScaleY = 1, Rotation;
	public float[] TransformMatrix = new float[] { 1, 0, 0, 1, 0, 0 };
	public bool Visible = true;
	public bool IsDirty = true;
	public bool HasAnimatedColor = false;
	public SwfLib.Data.ColorTransformRGB ColorTransform;
	public SwfLib.Data.ColorTransformRGBA ColorTransformRGBA;

	public float l = 1.0f;
	public Color EffectiveColor = new Color(1, 1, 1, 1);
}
