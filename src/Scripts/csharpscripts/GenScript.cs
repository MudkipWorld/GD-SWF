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

public partial class GenScript : Node {
    private SwfFile swfFile;
    private SwfDefinitionManager definitions;
    private const float TWIPS_TO_PIXELS = 1f / 20f;

    public Godot.Collections.Dictionary LoadSwf(string path, bool bakedData = true){
        using var file = System.IO.File.OpenRead(path);
        try { swfFile = SwfFile.ReadFrom(file); }
        catch (Exception e) { GD.PrintErr($"Failed to read SWF: {e.Message}"); return new Godot.Collections.Dictionary(); }

        definitions = new SwfDefinitionManager(swfFile);

        var exportDoc = new ExportDocument();
        foreach (var kvp in definitions.ShapeDict)
        {
            var shapeData = ShapeProcessor.ConvertShapeToSubPaths(kvp.Value.Last());
            shapeData.Svg = ShapeProcessor.ShapeToSvg(shapeData);
            exportDoc.Shapes[kvp.Key] = shapeData;
        }

        exportDoc.Sprites[0] = TimelineProcessor.ProcessTimeline(swfFile.Tags, definitions, bakedData);

        foreach (var kvp in definitions.SpriteDict)
        {
            if (kvp.Key == 0) continue;
            exportDoc.Sprites[kvp.Key] = TimelineProcessor.ProcessTimeline(kvp.Value.Tags, definitions, bakedData, kvp.Key);
        }

        var dict = ExportDocumentProcessor.ExportToDictionary(exportDoc);

        dict["SceneSize"] = new Godot.Collections.Dictionary
        {
            ["Width"] = swfFile.Header.FrameSize.XMax * TWIPS_TO_PIXELS,
            ["Height"] = swfFile.Header.FrameSize.YMax * TWIPS_TO_PIXELS
        };

        return dict;
    }

    public static class ExportDocumentProcessor{
        public static Godot.Collections.Dictionary ExportToDictionary(ExportDocument doc) {
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


                    Godot.Collections.Dictionary gradDict = null;
                    if (sub.Gradient != null)
                    {
                        var stopsArray = new Godot.Collections.Array();
                        foreach (var stop in sub.Gradient.Stops)
                        {
                            stopsArray.Add(new Godot.Collections.Dictionary
                            {
                                ["Offset"] = stop.Offset,
                                ["Color"] = new Godot.Collections.Dictionary
                                {
                                    ["R"] = stop.Color.R ,
                                    ["G"] = stop.Color.G ,
                                    ["B"] = stop.Color.B,
                                    ["A"] = stop.Color.A
                                }
                            });
                        }

                        gradDict = new Godot.Collections.Dictionary
                        {
                            ["X1"] = sub.Gradient.X1,
                            ["Y1"] = sub.Gradient.Y1,
                            ["X2"] = sub.Gradient.X2,
                            ["Y2"] = sub.Gradient.Y2,
                            ["Stops"] = stopsArray
                        };
                    }



                    subPathsArray.Add(new Godot.Collections.Dictionary
                    {
                        ["FillColor"] = fillColorDict,
                        ["Segments"] = segmentsArray,
                        ["Gradient"] = gradDict
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
                            ["LocalX"] = ft.TransformMatrix[4],
                            ["LocalY"] = -ft.TransformMatrix[5],

                            ["Lumi"] = ft.l,
                            ["EffectiveColor"] = ft.EffectiveColor

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
                    ["FrameNames"] = frameNamesArray,
                    ["SpriteName"] = spriteKvp.Value.SpriteName

                };
            }

            root["Sprites"] = sprites;

            return root;
        }

    }

}