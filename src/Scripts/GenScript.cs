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


public partial class GenScript : Node
{
    private SwfFile swfFile;
    private Dictionary<int, DefineSpriteTag> spriteDict = new();
    private Dictionary<int, List<dynamic>> shapeDict = new();

    private const float TWIPS_TO_PIXELS = 1f / 20f;

    public Godot.Collections.Dictionary LoadSwf(string path, bool baked_data = true)
    {
        using var file = System.IO.File.OpenRead(path);
        swfFile = SwfFile.ReadFrom(file);

        BuildDefinitionDictionaries();

        var exportDoc = new ExportDocument();

        foreach (var kvp in shapeDict)
        {
            var shapeToUse = kvp.Value.Last();
            var shapeData = ConvertShapeToSubPaths(shapeToUse);
            shapeData.Svg = ShapeToSvg(shapeData);
            exportDoc.Shapes[kvp.Key] = shapeData;
        }

        exportDoc.Sprites[0] = ProcessTimeline(swfFile.Tags, baked_data);

        foreach (var kvp in spriteDict)
        {
            if (kvp.Key == 0) continue;
            exportDoc.Sprites[kvp.Key] = ProcessTimeline(kvp.Value.Tags, baked_data);
        }

        var dict = ExportDocumentToDictionary(exportDoc);

        float stageWidth = swfFile.Header.FrameSize.XMax * TWIPS_TO_PIXELS;
        float stageHeight = swfFile.Header.FrameSize.YMax * TWIPS_TO_PIXELS;

        dict["SceneSize"] = new Godot.Collections.Dictionary
        {
            ["Width"] = stageWidth,
            ["Height"] = stageHeight
        };

        return dict;
    }


    private Godot.Collections.Dictionary ExportDocumentToDictionary(ExportDocument doc)
    {
        var root = new Godot.Collections.Dictionary();

        var shapes = new Godot.Collections.Dictionary();

        foreach (var shapeKvp in doc.Shapes)
        {
            var subPathsArray = new Godot.Collections.Array();

            foreach (var sub in shapeKvp.Value.SubPaths)
            {
                var segmentsArray = new Godot.Collections.Array();

                foreach (var seg in sub.Segments)
                {
                    var startDict = new Godot.Collections.Dictionary
                    {
                        ["IsEmpty"] = seg.Start == Vector2.Zero,
                        ["X"] = seg.Start.X,
                        ["Y"] = seg.Start.Y
                    };

                    var endDict = new Godot.Collections.Dictionary
                    {
                        ["IsEmpty"] = seg.End == Vector2.Zero,
                        ["X"] = seg.End.X,
                        ["Y"] = seg.End.Y
                    };

                    var controlDict = new Godot.Collections.Dictionary
                    {
                        ["IsEmpty"] = seg.Control == Vector2.Zero,
                        ["X"] = seg.Control.X,
                        ["Y"] = seg.Control.Y
                    };

                    var colorDict = new Godot.Collections.Dictionary
                    {
                        ["R"] = (int)(seg.Color.R * 255),
                        ["G"] = (int)(seg.Color.G * 255),
                        ["B"] = (int)(seg.Color.B * 255),
                        ["A"] = (int)(seg.Color.A * 255)
                    };

                    segmentsArray.Add(new Godot.Collections.Dictionary
                    {
                        ["Type"] = seg.Type,
                        ["Start"] = startDict,
                        ["End"] = endDict,
                        ["Control"] = controlDict,
                        ["Color"] = colorDict
                    });
                }

                var fillColorDict = new Godot.Collections.Dictionary
                {
                    ["R"] = (int)(sub.FillColor.R * 255),
                    ["G"] = (int)(sub.FillColor.G * 255),
                    ["B"] = (int)(sub.FillColor.B * 255),
                    ["A"] = (int)(sub.FillColor.A * 255)
                };

                subPathsArray.Add(new Godot.Collections.Dictionary
                {
                    ["FillColor"] = fillColorDict,
                    ["Segments"] = segmentsArray
                });
            }

            shapes[shapeKvp.Key] = new Godot.Collections.Dictionary
            {
                ["SubPaths"] = subPathsArray
            };
        }

        root["Shapes"] = shapes;

        var sprites = new Godot.Collections.Dictionary();

        foreach (var spriteKvp in doc.Sprites)
        {
            var childrenArray = new Godot.Collections.Array();
            foreach (var c in spriteKvp.Value.Children)
            {
                childrenArray.Add(new Godot.Collections.Dictionary
                {
                    ["ID"] = c.ID,
                    ["Type"] = c.Type
                });
            }

            var framesArray = new Godot.Collections.Array();
            foreach (var frame in spriteKvp.Value.Frames)
            {
                var frameDict = new Godot.Collections.Dictionary();
                foreach (var f in frame)
                {
                    var ft = f.Value;
                    var matrixArray = new Godot.Collections.Array
                    {
                        ft.TransformMatrix[0],
                        ft.TransformMatrix[1],
                        ft.TransformMatrix[2],
                        ft.TransformMatrix[3],
                        ft.TransformMatrix[4],
                        ft.TransformMatrix[5]
                    };

                    frameDict[f.Key] = new Godot.Collections.Dictionary
                    {
                        ["SymbolID"] = ft.SymbolID,
                        ["Depth"] = ft.Depth,
                        ["X"] = ft.X,
                        ["Y"] = ft.Y,
                        ["ScaleX"] = ft.ScaleX,
                        ["ScaleY"] = ft.ScaleY,
                        ["Rotation"] = ft.Rotation,
                        ["TransformMatrix"] = matrixArray,
                        ["Visible"] = ft.Visible,
                        ["LocalX"] = ft.TransformMatrix[4] ,
                        ["LocalY"] = -ft.TransformMatrix[5] 

                    };

                }
                
                
                framesArray.Add(frameDict);
            }

            var frameNamesArray = new Godot.Collections.Array();
            foreach (var name in spriteKvp.Value.FrameNames)
                frameNamesArray.Add(name);

            sprites[spriteKvp.Key] = new Godot.Collections.Dictionary
            {
                ["Children"] = childrenArray,
                ["Frames"] = framesArray,
                ["FrameNames"] = frameNamesArray
            };
        }

        root["Sprites"] = sprites;

        return root;
    }


    private Dictionary<int, Vector2> GetSpriteLocalPositions(DefineSpriteTag sprite)
    {
        var locals = new Dictionary<int, Vector2>();

        foreach (var tag in sprite.Tags)
        {
            switch (tag)
            {
                case PlaceObjectTag p1:
                    locals[p1.CharacterID] = SwfMatrixToLocal(p1.Matrix);
                    break;

                case PlaceObject2Tag p2:
                    if (!p2.HasMatrix) continue;
                    int childId = p2.HasCharacter ? p2.CharacterID : 0;
                    locals[childId] = SwfMatrixToLocal(p2.Matrix);
                    break;
            }
        }

        return locals;
    }

    private Vector2 SwfMatrixToLocal(SwfMatrix m)
    {
        const float TWIPS_TO_PIXELS = 1f / 20f;
        return new Vector2(m.TranslateX * TWIPS_TO_PIXELS, m.TranslateY * TWIPS_TO_PIXELS);
    }


    private void BuildDefinitionDictionaries()
    {
        spriteDict.Clear();
        shapeDict.Clear();

        void RecurseDefinitions(IEnumerable<SwfTagBase> tags)
        {
            foreach (var tag in tags)
            {
                switch (tag)
                {
                    case DefineShapeTag s:
                    case DefineShape2Tag s2:
                    case DefineShape3Tag s3:
                    case DefineShape4Tag s4:
                        AddShape(tag);
                        break;

                    case DefineSpriteTag sprite:
                        spriteDict[sprite.SpriteID] = sprite;
                        RecurseDefinitions(sprite.Tags);
                        break;
                }
            }
        }

        void AddShape(dynamic shape)
        {
            int id = shape.ShapeID;
            if (!shapeDict.TryGetValue(id, out var list))
            {
                list = new List<dynamic>();
                shapeDict[id] = list;
            }
            list.Add(shape);
        }

        if (swfFile != null)
            RecurseDefinitions(swfFile.Tags);
    }

    private void ExportSwfToJson(string outputPath)
    {
        if (swfFile == null) return;

        var exportDoc = new ExportDocument();

        foreach (var kvp in shapeDict)
        {
            var shapeToUse = kvp.Value.Last();
            var shapeData = ConvertShapeToSubPaths(shapeToUse);
            shapeData.Svg = ShapeToSvg(shapeData);
            exportDoc.Shapes[kvp.Key] = shapeData;
        }

        exportDoc.Sprites[0] = ProcessTimeline(swfFile.Tags);

        foreach (var kvp in spriteDict)
        {
            if (kvp.Key == 0) continue;
            exportDoc.Sprites[kvp.Key] = ProcessTimeline(kvp.Value.Tags);
        }

        var json = JsonSerializer.Serialize(exportDoc, new JsonSerializerOptions { WriteIndented = true });
        System.IO.File.WriteAllText(outputPath, json);
        GD.Print("Export complete!");
    }

private SpriteExportData ProcessTimeline(IEnumerable<SwfTagBase> tags, bool bakeFrames = true)
{
    var displayList = new Dictionary<int, FrameTag>();
    var frames = new List<Dictionary<int, FrameTag>>();
    var children = new Dictionary<int, string>();
    var frameNames = new List<string>();
    string pendingLabel = null;

    var labelCounts = new Dictionary<string, int>();
    var removedDepths = new HashSet<int>();

    FrameTag CloneFrameTag(FrameTag source)
    {
        if (source == null) return null;
        return new FrameTag
        {
            SymbolID = source.SymbolID,
            Depth = source.Depth,
            X = source.X,
            Y = source.Y,
            ScaleX = source.ScaleX,
            ScaleY = source.ScaleY,
            Rotation = source.Rotation,
            TransformMatrix = source.TransformMatrix != null ? (float[])source.TransformMatrix.Clone() : null,
            Visible = source.Visible,
            IsDirty = source.IsDirty
        };
    }

    Dictionary<int, FrameTag> lastFrame = null;

    float localX = 0f;
    float localY = 0f;
    var spriteTag = tags.OfType<DefineSpriteTag>().FirstOrDefault();
    if (spriteTag != null)
    {
        var locals = GetSpriteLocalPositions(spriteTag);
        if (locals.Count > 0)
        {
            var first = locals.First().Value;
            localX = first.X;
            localY = first.Y;
        }
    }

    var firstFrameData = new Dictionary<int, FrameTag>();
    int currentFrameIndex = 0;


    foreach (var tag in tags)
    {
        switch (tag)
        {
            case FrameLabelTag labelTag:
                string name = labelTag.Name;
                if (!string.IsNullOrEmpty(name))
                {
                    if (labelCounts.ContainsKey(name))
                    {
                        labelCounts[name]++;
                        name += labelCounts[name];
                    }
                    else
                    {
                        labelCounts[name] = 1;
                    }

                    pendingLabel = string.IsNullOrEmpty(pendingLabel) ? name : pendingLabel + ", " + name;
                }
                break;

            case ShowFrameTag:
                var frameDict = new Dictionary<int, FrameTag>();
                bool isAnimationStart = !bakeFrames && !string.IsNullOrEmpty(pendingLabel);

                foreach (var kvp in displayList)
                {
                    var f = kvp.Value;
                    var clone = CloneFrameTag(f);

                    if (!firstFrameData.ContainsKey(f.SymbolID))
                        firstFrameData[f.SymbolID] = CloneFrameTag(f);
                    

                    if (bakeFrames || f.IsDirty || isAnimationStart)
                        frameDict[kvp.Key] = clone;
                }

                if (!bakeFrames && lastFrame != null)
                {
                    foreach (var kvp in lastFrame)
                    {
                        int depth = kvp.Key;
                        if (removedDepths.Contains(depth)) continue;
                        if (!frameDict.ContainsKey(depth))
                        {
                            var carryover = CloneFrameTag(kvp.Value);
                            carryover.IsDirty = false;
                            frameDict[depth] = carryover;

                          
                            if (!firstFrameData.ContainsKey(carryover.SymbolID))
                                firstFrameData[carryover.SymbolID] = CloneFrameTag(carryover);
                           
                        }
                    }
                }

                frames.Add(frameDict);
                frameNames.Add(pendingLabel);
                pendingLabel = null;
                removedDepths.Clear();

                lastFrame = frameDict
                    .Where(kvp => kvp.Value.Visible)
                    .ToDictionary(k => k.Key, k => CloneFrameTag(k.Value));

                currentFrameIndex++;
                break;

            case PlaceObjectTag p1:
                UpdateDisplayObject(displayList, children, p1.CharacterID, p1.Depth, p1.Matrix, true, true);
                break;

            case PlaceObject2Tag p2:
                if (!displayList.ContainsKey(p2.Depth) && !p2.HasCharacter) break;

                int characterId = p2.HasCharacter ? p2.CharacterID : displayList[p2.Depth].SymbolID;
                bool isNew = !displayList.ContainsKey(p2.Depth);
                UpdateDisplayObject(displayList, children, characterId, p2.Depth, p2.Matrix, isNew, p2.HasMatrix);
                break;

            case RemoveObject2Tag r:
                removedDepths.Add(r.Depth);
                if (displayList.ContainsKey(r.Depth))
                    displayList.Remove(r.Depth);
                break;
        }
    }

    var spriteData = new SpriteExportData
    {
        Children = children.Select(kvp => new ChildInfo { ID = kvp.Key, Type = kvp.Value }).ToList(),
        Frames = frames,
        FrameNames = frameNames,
        LocalX = localX,
        LocalY = localY,
        FirstFrameData = firstFrameData
    };

    spriteData.MaxNestingDepth = ComputeSpriteDepth(spriteTag?.SpriteID ?? 0);

    return spriteData;
}

    private void UpdateDisplayObject( Dictionary<int, FrameTag> displayList, Dictionary<int, string> children, int characterId, int depth, SwfMatrix matrix,bool hasCharacter, bool hasMatrix)
    {
        displayList.TryGetValue(depth, out var prev);

        float x = prev?.X ?? 0;
        float y = prev?.Y ?? 0;
        float sx = prev?.ScaleX ?? 1;
        float sy = prev?.ScaleY ?? 1;
        float rot = prev?.Rotation ?? 0;
        float[] mat = prev?.TransformMatrix != null ? (float[])prev.TransformMatrix.Clone() : new float[] { 1, 0, 0, 1, 0, 0 };

        if (hasMatrix)
        {
            x = matrix.TranslateX * TWIPS_TO_PIXELS;
            y = matrix.TranslateY * TWIPS_TO_PIXELS;

            float a = (float)matrix.ScaleX;
            float b = (float)matrix.RotateSkew0;
            float c = (float)matrix.RotateSkew1;
            float d = (float)matrix.ScaleY;

            sx = (float)Math.Sqrt(a * a + b * b);
            sy = (float)Math.Sqrt(c * c + d * d);
            rot = -(float)Math.Atan2(b, a) * (180f / Mathf.Pi);

            mat[0] = a; mat[1] = b; mat[2] = c; mat[3] = d; mat[4] = x; mat[5] = y;
        }

        bool matrixChanged = prev == null || !MatrixEquals(prev.TransformMatrix, mat);

        bool isDirty =
            prev == null ||
            prev.SymbolID != characterId ||
            prev.Visible == false ||
            matrixChanged;


        if (prev != null)
        {
            if (hasCharacter && prev.SymbolID != characterId)
            {
                prev.SymbolID = characterId;
                isDirty = true;
            }

            prev.X = x; prev.Y = y; prev.ScaleX = sx; prev.ScaleY = sy; prev.Rotation = rot; prev.TransformMatrix = mat; prev.Visible = true;
            prev.IsDirty = isDirty;
            displayList[depth] = prev;
        }
        else
        {
            displayList[depth] = new FrameTag
            {
                SymbolID = characterId,
                Depth = depth,
                X = x,
                Y = y,
                ScaleX = sx,
                ScaleY = sy,
                Rotation = rot,
                TransformMatrix = mat,
                Visible = true,
                IsDirty = true
            };
        }

        if (!children.ContainsKey(characterId))
            children[characterId] = shapeDict.ContainsKey(characterId) ? "Shape" : "Sprite";
    }

    private bool MatrixEquals(float[] a, float[] b)
    {
        if (a == null || b == null) return false;

        const float EPS = 0.0001f;

        for (int i = 0; i < 6; i++)
            if (Math.Abs(a[i] - b[i]) > EPS)
                return false;

        return true;
    }

    private ShapeData ConvertShapeToSubPaths(dynamic shapeTag)
    {
        var shapeData = new ShapeData();

        float x = 0, y = 0;
        int? fill0 = null, fill1 = null;
        int styleTableId = 0;

        var fillStyleTables = new Dictionary<int, dynamic>();
        fillStyleTables[styleTableId] = shapeTag.FillStyles;

        var fillEdges = new Dictionary<(int tableId, int fillIndex), List<Edge>>();

        void AddEdge(int table, int? fill, Edge e)
        {
            if (!fill.HasValue) return;
            var key = (table, fill.Value);
            if (!fillEdges.TryGetValue(key, out var list))
                fillEdges[key] = list = new List<Edge>();
            list.Add(e);
        }

        foreach (var record in shapeTag.ShapeRecords)
        {
            switch (record)
            {
                case SwfLib.Shapes.Records.StyleChangeShapeRecord sc:
                    if (sc.StateNewStyles)
                    {
                        styleTableId++;
                        try
                        {
                            fillStyleTables[styleTableId] = ((dynamic)sc).FillStyles ?? fillStyleTables[styleTableId - 1];
                        }
                        catch { fillStyleTables[styleTableId] = fillStyleTables[styleTableId - 1]; }
                        fill0 = fill1 = null;
                    }

                    if (sc.StateMoveTo)
                    {
                        x = sc.MoveDeltaX * TWIPS_TO_PIXELS;
                        y = sc.MoveDeltaY * TWIPS_TO_PIXELS;
                    }
                    if (sc.FillStyle0.HasValue) fill0 = sc.FillStyle0 > 0 ? (int)sc.FillStyle0 - 1 : null;
                    if (sc.FillStyle1.HasValue) fill1 = sc.FillStyle1 > 0 ? (int)sc.FillStyle1 - 1 : null;
                    break;

                case SwfLib.Shapes.Records.StraightEdgeShapeRecord s:
                    var start = new Vector2(x, y);
                    var end = new Vector2(x + s.DeltaX * TWIPS_TO_PIXELS, y + s.DeltaY * TWIPS_TO_PIXELS);
                    AddEdge(styleTableId, fill1, new Edge { Start = start, End = end });
                    AddEdge(styleTableId, fill0, new Edge { Start = end, End = start });
                    x = end.X; y = end.Y;
                    break;

                case SwfLib.Shapes.Records.CurvedEdgeShapeRecord c:
                    start = new Vector2(x, y);
                    var ctrl = new Vector2(x + c.ControlDeltaX * TWIPS_TO_PIXELS, y + c.ControlDeltaY * TWIPS_TO_PIXELS);
                    end = new Vector2(ctrl.X + c.AnchorDeltaX * TWIPS_TO_PIXELS, ctrl.Y + c.AnchorDeltaY * TWIPS_TO_PIXELS);
                    AddEdge(styleTableId, fill1, new Edge { Start = start, Control = ctrl, End = end });
                    AddEdge(styleTableId, fill0, new Edge { Start = end, Control = ctrl, End = start });
                    x = end.X; y = end.Y;
                    break;
            }
        }

        foreach (var kvp in fillEdges)
        {
            var (tableId, fillIndex) = kvp.Key;
            var fillStyles = fillStyleTables[tableId];
            if (fillStyles == null || fillIndex < 0 || fillIndex >= fillStyles.Count) continue;

            var fillStyle = fillStyles[fillIndex];
            var color = GetGradientStartColor(fillStyle) ?? new Color(1, 1, 1, 1);

            foreach (var loop in BuildLoops(kvp.Value))
            {
                var sub = new SubPath { FillColor = color };
                shapeData.SubPaths.Add(sub);

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

                sub.Segments.Add(new PathSegment
                {
                    Type = "line",
                    Start = loop[^1].End,
                    End = loop[0].Start,
                    Color = color
                });
            }
        }

        return shapeData;
    }

    private List<List<Edge>> BuildLoops(List<Edge> edges)
    {
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

public string ShapeToSvg(ShapeData shape)
{
    if (shape.SubPaths.Count == 0) return "";

    var sb = new StringBuilder();
    var defs = new StringBuilder();
    int gradientCounter = 0;

    sb.AppendLine(@"<?xml version=""1.0"" encoding=""UTF-8"" standalone=""no""?>");
    sb.AppendLine("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">");

    foreach (var sub in shape.SubPaths)
    {
        var pathSb = new StringBuilder();

        foreach (var seg in sub.Segments)
        {
            switch (seg.Type)
            {
                case "move": pathSb.AppendFormat("M{0} {1} ", seg.Start.X, seg.Start.Y); break;
                case "line": pathSb.AppendFormat("L{0} {1} ", seg.End.X, seg.End.Y); break;
                case "curve": pathSb.AppendFormat("Q{0} {1} {2} {3} ", seg.Control.X, seg.Control.Y, seg.End.X, seg.End.Y); break;
            }
        }

        string fillAttr;
        float alpha = sub.FillColor.A;

        if (sub.Gradient != null && sub.Gradient.Stops.Count > 0)
        {
            if (sub.GradientId < 0)
                sub.GradientId = gradientCounter++;

            string gradName = $"grad{sub.GradientId}";
            fillAttr = $"url(#{gradName})";

            defs.AppendLine($"<linearGradient id=\"{gradName}\" x1=\"{sub.Gradient.X1}\" y1=\"{sub.Gradient.Y1}\" x2=\"{sub.Gradient.X2}\" y2=\"{sub.Gradient.Y2}\" gradientUnits=\"userSpaceOnUse\">");
            foreach (var stop in sub.Gradient.Stops)
            {
                string stopColor = $"{(int)(stop.Color.R * 255):X2}{(int)(stop.Color.G * 255):X2}{(int)(stop.Color.B * 255):X2}";
                defs.AppendLine($"<stop offset=\"{stop.Offset:F6}\" stop-color=\"#{stopColor}\" stop-opacity=\"{stop.Color.A:F6}\" />");
            }
            defs.AppendLine("</linearGradient>");
        }
        else
        {
            string hex = $"{(int)(sub.FillColor.R * 255):X2}{(int)(sub.FillColor.G * 255):X2}{(int)(sub.FillColor.B * 255):X2}";
            fillAttr = "#" + hex;
        }

        sb.AppendFormat(
            "<path d=\"{0}\" fill=\"{1}\" fill-opacity=\"{2:F6}\" stroke=\"none\" fill-rule=\"nonzero\"/>\n",
            pathSb.ToString().TrimEnd(),
            fillAttr,
            alpha
        );
    }

    // insert gradient definitions
    if (defs.Length > 0)
        sb.Insert(sb.ToString().IndexOf("<svg") + 5, "<defs>" + defs.ToString() + "</defs>\n");

    sb.AppendLine("</svg>");
    return sb.ToString();
}

    private static float Distance(Vector2 a, Vector2 b)
    {
        return (a - b).Length();
    }

    private int ComputeSpriteDepth(int spriteID, HashSet<int> visited = null)
    {
        if (visited == null) visited = new HashSet<int>();
        if (visited.Contains(spriteID)) return 0; // Avoid cycles
        visited.Add(spriteID);

        if (!spriteDict.TryGetValue(spriteID, out var sprite)) return 0;

        int maxChildDepth = 0;

        foreach (var tag in sprite.Tags)
        {
            switch (tag)
            {
                case PlaceObjectTag p:
                    if (spriteDict.ContainsKey(p.CharacterID))
                        maxChildDepth = Math.Max(maxChildDepth, 1 + ComputeSpriteDepth(p.CharacterID, new HashSet<int>(visited)));
                    break;
                case PlaceObject2Tag p2:
                    if (p2.HasCharacter && spriteDict.ContainsKey(p2.CharacterID))
                        maxChildDepth = Math.Max(maxChildDepth, 1 + ComputeSpriteDepth(p2.CharacterID, new HashSet<int>(visited)));
                    break;
            }
        }

        return maxChildDepth;
    }


    Color GetGradientStartColor(dynamic fillStyle)
    {
        switch (fillStyle)
        {
            case SwfLib.Shapes.FillStyles.LinearGradientFillStyleRGB linear:
                var first = linear.Gradient.GradientRecords[0];
                return new Color(first.Color.Red / 255f, first.Color.Green / 255f, first.Color.Blue / 255f, 1.0f);

            case SwfLib.Shapes.FillStyles.RadialGradientFillStyleRGB radial:
                var firstR = radial.Gradient.GradientRecords[0];
                return new Color(firstR.Color.Red / 255f, firstR.Color.Green / 255f, firstR.Color.Blue / 255f, 1.0f);

            case SwfLib.Shapes.FillStyles.LinearGradientFillStyleRGBA linearR:
                var firstLR = linearR.Gradient.GradientRecords[0];
                return new Color(firstLR.Color.Red / 255f, firstLR.Color.Green / 255f, firstLR.Color.Blue / 255f, firstLR.Color.Alpha / 255f);

            case SwfLib.Shapes.FillStyles.RadialGradientFillStyleRGBA radialR:
                var firstRR = radialR.Gradient.GradientRecords[0];
                return new Color(firstRR.Color.Red / 255f, firstRR.Color.Green / 255f, firstRR.Color.Blue / 255f, firstRR.Color.Alpha / 255f);

            case SwfLib.Shapes.FillStyles.SolidFillStyleRGB rgb:
                return new Color(rgb.Color.Red / 255f, rgb.Color.Green / 255f, rgb.Color.Blue / 255f, 1f);

            case SwfLib.Shapes.FillStyles.SolidFillStyleRGBA rgba:
                return new Color(rgba.Color.Red / 255f, rgba.Color.Green / 255f, rgba.Color.Blue / 255f, rgba.Color.Alpha / 255f);

            default:
                return new Color(1, 1, 1, 1);
        }
    }


    public class ExportDocument { public Dictionary<int, ShapeData> Shapes = new(); public Dictionary<int, SpriteExportData> Sprites = new(); }
    public class SpriteExportData { public List<ChildInfo> Children = new(); public List<Dictionary<int, FrameTag>> Frames = new(); public List<string> FrameNames = new(); public float LocalX, LocalY;  public int MaxNestingDepth = 0; public Dictionary<int, FrameTag> FirstFrameData = new();}
    public class ChildInfo { public int ID; public string Type = "Shape"; }
    public class ShapeData { public List<SubPath> SubPaths = new(); public string Svg = ""; }
    public class SubPath { public Color FillColor = new(1, 1, 1, 1); public List<PathSegment> Segments = new(); public Vector2 LastPoint;     public GradientInfo Gradient = null;  public int GradientId = -1;}


    public class GradientInfo
    {
        public float X1, Y1, X2, Y2;
        public List<GradientStop> Stops;
    }

    public class GradientStop
    {
        public Color Color;
        public float Offset; // 0 to 1
    }

    public class PathSegment { public string Type = "line"; public Vector2 Start, Control, End; public Color Color = new(1, 1, 1, 1); }
    public class FrameTag {
        public int SymbolID, Depth;
        public float X, Y, ScaleX = 1, ScaleY = 1, Rotation;
        public float LocalX, LocalY;
        public float[] TransformMatrix = new float[] { 1, 0, 0, 1, 0, 0 };
        public bool Visible = true;
        public bool IsDirty = true;

        public FrameTag Clone() => (FrameTag)MemberwiseClone();
    }
    public class Edge
    {
        public Vector2 Start;
        public Vector2? Control;
        public Vector2 End;
        public int? FillIndex;

        public Edge() { }

        public Edge(Vector2 start, Vector2? control, Vector2 end, int? fillIndex)
        {
            Start = start;
            Control = control;
            End = end;
            FillIndex = fillIndex;
        }

        public Edge Reversed() => new Edge(End, Control, Start, FillIndex);
    }
}
