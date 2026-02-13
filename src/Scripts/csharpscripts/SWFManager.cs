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

public class SwfDefinitionManager
{
    public Dictionary<int, DefineSpriteTag> SpriteDict { get; } = new();
    public Dictionary<int, List<dynamic>> ShapeDict { get; } = new();
    public Dictionary<int, string> SymbolNames { get; } = new();

    public SwfDefinitionManager(SwfFile swf)
    {
        if (swf == null) return;
        RecurseDefinitions(swf.Tags);
    }

    private void RecurseDefinitions(IEnumerable<SwfTagBase> tags)
    {
        foreach (var tag in tags)
        {
            switch (tag)
            {
                case SymbolClassTag sym:
                    foreach (var r in sym.References) SymbolNames[r.SymbolID] = r.SymbolName;
                    break;

                case DefineShapeTag:
                case DefineShape2Tag:
                case DefineShape3Tag:
                case DefineShape4Tag:
                    AddShape(tag);
                    break;

                case DefineSpriteTag sprite:
                    SpriteDict[sprite.SpriteID] = sprite;
                    RecurseDefinitions(sprite.Tags);
                    break;
            }
        }
    }

    private void AddShape(dynamic shape)
    {
        int id = shape.ShapeID;
        if (!ShapeDict.TryGetValue(id, out var list)) ShapeDict[id] = list = new List<dynamic>();
        list.Add(shape);
    }
}