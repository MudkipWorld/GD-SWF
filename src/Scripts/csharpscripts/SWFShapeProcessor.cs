using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using SwfLib;
using SwfLib.Tags;
using SwfLib.Tags.ShapeTags;
using SwfLib.Data;
using SwfLib.Tags.DisplayListTags;
using SwfLib.Tags.ControlTags;
using System.Text.Json;
using System.IO;
 

public static class ShapeProcessor{
	private const float TWIPS_TO_PIXELS = 1f / 20f;

	public static ShapeData ConvertShapeToSubPaths(dynamic shapeTag){
		var shapeData = new ShapeData();

		float x = 0, y = 0;
		int? fill0 = null, fill1 = null;
		int? lineStyle = null;
		int styleTableId = 0;

		var fillStyleTables = new Dictionary<int, dynamic>();
		var lineStyleTables = new Dictionary<int, dynamic>();
		fillStyleTables[styleTableId] = shapeTag.FillStyles;
		lineStyleTables[styleTableId] = shapeTag.LineStyles;

		var fillEdges = new Dictionary<(int tableId, int fillIndex), List<Edge>>();
		var strokeEdges = new Dictionary<(int tableId, int lineIndex), List<Edge>>();

		foreach (var record in shapeTag.ShapeRecords){
			switch (record)
			{
				case SwfLib.Shapes.Records.StyleChangeShapeRecord sc:
					if (sc.StateNewStyles)
					{
						styleTableId++;
						fillStyleTables[styleTableId] =
							((dynamic)sc).FillStyles ?? fillStyleTables[styleTableId - 1];
						lineStyleTables[styleTableId] =
							((dynamic)sc).LineStyles ?? lineStyleTables[styleTableId - 1];
						fill0 = fill1 = lineStyle = null;
					}

					if (sc.StateMoveTo)
					{
						x = sc.MoveDeltaX * TWIPS_TO_PIXELS;
						y = sc.MoveDeltaY * TWIPS_TO_PIXELS;
					}

					if (sc.FillStyle0.HasValue)
						fill0 = sc.FillStyle0 > 0 ? (int)sc.FillStyle0 - 1 : null;
					if (sc.FillStyle1.HasValue)
						fill1 = sc.FillStyle1 > 0 ? (int)sc.FillStyle1 - 1 : null;
					if (sc.LineStyle.HasValue)
						lineStyle = sc.LineStyle > 0 ? (int)sc.LineStyle - 1 : null;
					break;

				case SwfLib.Shapes.Records.StraightEdgeShapeRecord s:
					{
						var start = new Vector2(x, y);
						var end = new Vector2(
							x + s.DeltaX * TWIPS_TO_PIXELS,
							y + s.DeltaY * TWIPS_TO_PIXELS
						);

						AddFillEdge(styleTableId, fill1, new Edge { Start = start, End = end }, fillEdges);
						AddFillEdge(styleTableId, fill0, new Edge { Start = end, End = start }, fillEdges);
						AddStrokeEdge(styleTableId, lineStyle, new Edge { Start = start, End = end }, strokeEdges);

						x = end.X;
						y = end.Y;
					}
					break;

				case SwfLib.Shapes.Records.CurvedEdgeShapeRecord c:
					{
						var start = new Vector2(x, y);
						var ctrl = new Vector2(
							x + c.ControlDeltaX * TWIPS_TO_PIXELS,
							y + c.ControlDeltaY * TWIPS_TO_PIXELS
						);
						var end = new Vector2(
							ctrl.X + c.AnchorDeltaX * TWIPS_TO_PIXELS,
							ctrl.Y + c.AnchorDeltaY * TWIPS_TO_PIXELS
						);

						AddFillEdge(styleTableId, fill1, new Edge { Start = start, Control = ctrl, End = end }, fillEdges);
						AddFillEdge(styleTableId, fill0, new Edge { Start = end, Control = ctrl, End = start }, fillEdges);
						AddStrokeEdge(styleTableId, lineStyle, new Edge { Start = start, Control = ctrl, End = end }, strokeEdges);

						x = end.X;
						y = end.Y;
					}
					break;
			}
		}


		foreach (var kvp in fillEdges)
		{
			var (tableId, fillIndex) = kvp.Key;
			var fillStyles = fillStyleTables[tableId];
			if (fillStyles == null || fillIndex < 0 || fillIndex >= fillStyles.Count)
				continue;

			var fillStyle = fillStyles[fillIndex];

			bool isGrad = IsGradient(fillStyle);
		
			var color = new Color(1.0f, 1.0f, 1.0f, 1.0f);

			foreach (var loop in BuildLoops(kvp.Value))
			{
				var sub = new SubPath { FillColor = color };
				shapeData.SubPaths.Add(sub);

				if (isGrad)
				{
					sub.Gradient = GetGradientInfo(fillStyle);
					sub.FillColor = new Color(sub.Gradient.Stops[0].Color.R, sub.Gradient.Stops[0].Color.G, sub.Gradient.Stops[0].Color.B, 1.0f);
				}
				else
				{
					sub.FillColor = getFillColor(fillStyle);
				}


				bool first = true;
				foreach (var e in loop)
				{
					if (first)
					{
						sub.Segments.Add(new PathSegment
						{
							Type = "move",
							Start = e.Start,
							End = e.Start,
							Color = color
						});
						first = false;
					}

					sub.Segments.Add(new PathSegment
					{
						Type = e.Control.HasValue ? "curve" : "line",
						Start = e.Start,
						Control = e.Control ?? Vector2.Zero,
						End = e.End,
						Color = color
					});
				}
			}
		}


		foreach (var kvp in strokeEdges)
		{
			var (tableId, lineIndex) = kvp.Key;
			var lineStyles = lineStyleTables[tableId];
			if (lineStyles == null || lineIndex < 0 || lineIndex >= lineStyles.Count)
				continue;

			dynamic ls = lineStyles[lineIndex];
			float width = ls.Width * TWIPS_TO_PIXELS;
			Color strokeColor = new Color(0, 0, 0, 1);

			if (ls is SwfLib.Shapes.LineStyles.LineStyleRGBA rgba)
				strokeColor = new Color(
					rgba.Color.Red / 255f,
					rgba.Color.Green / 255f,
					rgba.Color.Blue / 255f,
					rgba.Color.Alpha / 255f
				);
			else if (ls is SwfLib.Shapes.LineStyles.LineStyleRGB rgb)
				strokeColor = new Color(
					rgb.Color.Red / 255f,
					rgb.Color.Green / 255f,
					rgb.Color.Blue / 255f,
					1f
				);

			foreach (var loop in BuildLoops(kvp.Value))
			{
				var stroke = new StrokePath
				{
					StrokeColor = strokeColor,
					Width = width
				};

				bool first = true;
				foreach (var e in loop)
				{
					if (first)
					{
						stroke.Segments.Add(new PathSegment
						{
							Type = "move",
							Start = e.Start,
							End = e.Start,
							Color = strokeColor
						});
						first = false;
					}

					stroke.Segments.Add(new PathSegment
					{
						Type = e.Control.HasValue ? "curve" : "line",
						Start = e.Start,
						Control = e.Control ?? Vector2.Zero,
						End = e.End,
						Color = strokeColor
					});
				}

				shapeData.Strokes.Add(stroke);
			}
		}

		return shapeData;
	}

	public static bool IsGradient(object fillStyle)
	{
		return fillStyle is SwfLib.Shapes.FillStyles.LinearGradientFillStyleRGB ||
			fillStyle is SwfLib.Shapes.FillStyles.LinearGradientFillStyleRGBA ||
			fillStyle is SwfLib.Shapes.FillStyles.RadialGradientFillStyleRGB ||
			fillStyle is SwfLib.Shapes.FillStyles.RadialGradientFillStyleRGBA ||
			fillStyle is SwfLib.Shapes.FillStyles.FocalGradientFillStyleRGB ||
			fillStyle is SwfLib.Shapes.FillStyles.FocalGradientFillStyleRGBA;
	}

	public static  List<List<Edge>> BuildLoops(List<Edge> edges){
		var unused = new List<Edge>(edges);
		var loops = new List<List<Edge>>();

		while (unused.Count > 0)
		{
			var loop = new List<Edge>();
			var e = unused[0]; unused.RemoveAt(0);
			loop.Add(e);
			var current = e.End;

			while ((current - loop[0].Start).Length() > 0.001f)
			{
				int idx = unused.FindIndex(x => (x.Start - current).Length() < 0.001f);
				if (idx == -1) break;
				e = unused[idx]; unused.RemoveAt(idx);
				loop.Add(e);
				current = e.End;
			}

			loops.Add(loop);
		}

		return loops;
	}

	private static void AddFillEdge(int table, int? fill, Edge e, Dictionary<(int tableId, int fillIndex), List<Edge>> fillEdges){
		if (!fill.HasValue) return;
		var key = (table, fill.Value);
		if (!fillEdges.TryGetValue(key, out var list))
			fillEdges[key] = list = new List<Edge>();
		list.Add(e);
	}

	private static void AddStrokeEdge(int table, int? line, Edge e, Dictionary<(int tableId, int lineIndex), List<Edge>> strokeEdges){
		if (!line.HasValue) return;
		var key = (table, line.Value);
		if (!strokeEdges.TryGetValue(key, out var list))
			strokeEdges[key] = list = new List<Edge>();
		list.Add(e);
	}

	public static string ShapeToSvg(ShapeData shape)
		{
			if (shape.SubPaths.Count == 0 && shape.Strokes.Count == 0)
				return "";

			var sb = new StringBuilder();
			sb.AppendLine(@"<?xml version=""1.0"" encoding=""UTF-8""?>");
			sb.AppendLine("<svg xmlns=\"http://www.w3.org/2000/svg\">");

			foreach (var sub in shape.SubPaths)
			{
				var pathSb = new StringBuilder();

				foreach (var seg in sub.Segments)
				{
					if (seg.Type == "move")
						pathSb.AppendFormat("M{0} {1} ", seg.Start.X, seg.Start.Y);
					else if (seg.Type == "line")
						pathSb.AppendFormat("L{0} {1} ", seg.End.X, seg.End.Y);
					else
						pathSb.AppendFormat(
							"Q{0} {1} {2} {3} ",
							seg.Control.X, seg.Control.Y,
							seg.End.X, seg.End.Y
						);
				}

				string hex =
					$"{(int)(sub.FillColor.R * 255):X2}" +
					$"{(int)(sub.FillColor.G * 255):X2}" +
					$"{(int)(sub.FillColor.B * 255):X2}";

				sb.AppendFormat(
					"<path d=\"{0}\" fill=\"#{1}\" fill-opacity=\"{2:F6}\" stroke=\"none\" />\n",
					pathSb.ToString().TrimEnd(),
					hex,
					sub.FillColor.A
				);
			}

			foreach (var stroke in shape.Strokes)
			{
				var pathSb = new StringBuilder();

				foreach (var seg in stroke.Segments)
				{
					if (seg.Type == "move")
						pathSb.AppendFormat("M{0} {1} ", seg.Start.X, seg.Start.Y);
					else if (seg.Type == "line")
						pathSb.AppendFormat("L{0} {1} ", seg.End.X, seg.End.Y);
					else
						pathSb.AppendFormat(
							"Q{0} {1} {2} {3} ",
							seg.Control.X, seg.Control.Y,
							seg.End.X, seg.End.Y
						);
				}

				string hex =
					$"{(int)(stroke.StrokeColor.R * 255):X2}" +
					$"{(int)(stroke.StrokeColor.G * 255):X2}" +
					$"{(int)(stroke.StrokeColor.B * 255):X2}";

				sb.AppendFormat(
					"<path d=\"{0}\" fill=\"none\" stroke=\"#{1}\" stroke-opacity=\"{2:F6}\" stroke-width=\"{3:F6}\" stroke-linecap=\"round\" stroke-linejoin=\"round\" />\n",
					pathSb.ToString().TrimEnd(),
					hex,
					stroke.StrokeColor.A,
					stroke.Width
				);
			}

			sb.AppendLine("</svg>");
			return sb.ToString();
		}

	public static Color getFillColor(dynamic fillStyle) {

			switch (fillStyle)
			{
				case SwfLib.Shapes.FillStyles.SolidFillStyleRGB rgb:
					return new Color(rgb.Color.Red / 255f, rgb.Color.Green / 255f, rgb.Color.Blue / 255f, 1f);

				case SwfLib.Shapes.FillStyles.SolidFillStyleRGBA rgba:
					return new Color(rgba.Color.Red / 255f, rgba.Color.Green / 255f, rgba.Color.Blue / 255f, rgba.Color.Alpha / 255f);

				default:
					return new Color(1, 1, 1, 1);
			}
		}

	public static GradientInfo GetGradientInfo(dynamic fillStyle)
	{
		GradientInfo info = new GradientInfo();
		info.Stops = new List<GradientStop>();

		Transform2D mat;
		Vector2 start, end;

		switch (fillStyle)
		{
			case SwfLib.Shapes.FillStyles.LinearGradientFillStyleRGB linear:
				mat = linear.GradientMatrix.ToGodotTransform();

				foreach (var rec in linear.Gradient.GradientRecords)                
				{
					Color color = new Color(rec.Color.Red / 255f, rec.Color.Green / 255f, rec.Color.Blue / 255f, 1f);
					//GD.Print(color);
					info.Stops.Add(new GradientStop
					{
						Offset = rec.Ratio / 255f,
						Color = color
					});
				}

				start = mat.BasisXform(new Vector2(0, 0));
				end = mat.BasisXform(new Vector2(16384, 0));

				// Convert twips → pixels
				info.X1 = start.X / 20f;
				info.Y1 = start.Y / 20f;
				info.X2 = end.X / 20f;
				info.Y2 = end.Y / 20f;
				break;

			case SwfLib.Shapes.FillStyles.LinearGradientFillStyleRGBA linearR:
				mat = linearR.GradientMatrix.ToGodotTransform();

				foreach (var rec in linearR.Gradient.GradientRecords)
				{
					Color color = new Color(rec.Color.Red / 255f, rec.Color.Green / 255f, rec.Color.Blue / 255f, rec.Color.Alpha / 255f);
					//GD.Print(color);
					info.Stops.Add(new GradientStop
					{
						Offset = rec.Ratio / 255f,
						Color = color
					});
				}

				start = mat.BasisXform(new Vector2(0, 0));
				end = mat.BasisXform(new Vector2(16384, 0));

				info.X1 = start.X / 20f;
				info.Y1 = start.Y / 20f;
				info.X2 = end.X / 20f;
				info.Y2 = end.Y / 20f;
				break;

			default:
				return null;
		}

		return info;
	}

	public static Transform2D ToGodotTransform(this SwfMatrix m)
	{
		return new Transform2D(
			(float)m.ScaleX, (float)m.RotateSkew0, m.TranslateX / 20f,
			(float)m.RotateSkew1, (float)m.ScaleY, m.TranslateY / 20f
		);
	}



}
