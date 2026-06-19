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
 
public static class TimelineProcessor{
	private const float TWIPS_TO_PIXELS = 1f / 20f;
	
public static SpriteExportData ProcessTimeline(IEnumerable<SwfTagBase> tags, SwfDefinitionManager defs, bool bakeFrames = true, int? spriteID = null)
{
	var displayList = new Dictionary<int, FrameTag>();
	var frames = new List<Dictionary<int, FrameTag>>();
	var children = new List<ChildInfo>();
	var frameNames = new List<string>();
	string pendingLabel = null;

	var labelCounts = new Dictionary<string, int>();
	var removedDepths = new HashSet<int>();
	Dictionary<int, FrameTag> lastFrame = null;

	float localX = 0f;
	float localY = 0f;

	var spriteTag = tags.OfType<DefineSpriteTag>().FirstOrDefault();

	var sprite_name = "";
	if (spriteID.HasValue && defs.SymbolNames.TryGetValue(spriteID.Value, out var n))
		sprite_name = n;

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


	var bakedTimeline = new Dictionary<int, Dictionary<int, FrameTag>>();

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
						labelCounts[name] = 1;

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

				var bakedFrame = new Dictionary<int, FrameTag>();
				foreach (var kvp in frameDict)
				{
					bakedFrame[kvp.Key] = CloneFrameTag(kvp.Value);
				}
				bakedTimeline[currentFrameIndex] = bakedFrame;

				lastFrame = frameDict
					.Where(kvp => kvp.Value.Visible)
					.ToDictionary(k => k.Key, k => CloneFrameTag(k.Value));

				currentFrameIndex++;
				break;

			case PlaceObjectTag p1:
				UpdateDisplayObject(displayList, children, p1.CharacterID, p1.Depth, p1.Matrix, true, true, null, defs);
				break;

			case PlaceObject2Tag p2:
				int symbolId2 = p2.HasCharacter ? p2.CharacterID :
								displayList.TryGetValue(p2.Depth, out var existing2) ? existing2.SymbolID : 0;
				bool isNewEntry2 = p2.HasCharacter || !displayList.ContainsKey(p2.Depth);
				object ct2 = p2.HasColorTransform ? (object)p2.ColorTransform : null;
				UpdateDisplayObject(displayList, children, symbolId2, p2.Depth, p2.Matrix, isNewEntry2, p2.HasMatrix, ct2, defs);
				break;

			case PlaceObject3Tag p3:
				int symbolId3 = p3.HasCharacter ? p3.CharacterID :
								displayList.TryGetValue(p3.Depth, out var existing3) ? existing3.SymbolID : 0;
				bool isNewEntry3 = p3.HasCharacter || !displayList.ContainsKey(p3.Depth);
				object ct3 = p3.HasColorTransform ? (object)p3.ColorTransform : null;
				UpdateDisplayObject(displayList, children, symbolId3, p3.Depth, p3.Matrix, isNewEntry3, p3.HasMatrix, ct3, defs);
				break;

			case RemoveObjectTag r:
				removedDepths.Add(r.Depth);
				displayList.Remove(r.Depth);
				break;

			case RemoveObject2Tag r2:
				removedDepths.Add(r2.Depth);
				displayList.Remove(r2.Depth);
				break;
		}
	}

	foreach (var frameEntry in bakedTimeline)
	{
		var frameIdx = frameEntry.Key;
		var frameDict = frameEntry.Value;

		var allDepths = frameDict.Keys.ToList();
		foreach (var kvp in frameDict)
		{
			var fTag = kvp.Value;
			if (!fTag.Visible)
				fTag.Visible = true;
		}
	}

	var spriteData = new SpriteExportData
	{
		Children = children,
		Frames = frames,
		FrameNames = frameNames,
		LocalX = localX,
		LocalY = localY,
		FirstFrameData = firstFrameData,
		SpriteName = sprite_name,
	};

	spriteData.MaxNestingDepth = ComputeSpriteDepth(spriteTag?.SpriteID ?? 0, defs);

	return spriteData;
}


	private static void UpdateDisplayObject(Dictionary<int, FrameTag> displayList, List<ChildInfo> children, int characterId, int depth, SwfMatrix matrix, bool hasCharacter, bool hasMatrix, object colorTransform = null, SwfDefinitionManager defs = null){
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

		FrameTag frame;
		if (prev != null)
		{
			frame = prev;

			if (hasCharacter && prev.SymbolID != characterId)
			{
				frame.SymbolID = characterId;
				isDirty = true;
			}

			frame.X = x;
			frame.Y = y;
			frame.ScaleX = sx;
			frame.ScaleY = sy;
			frame.Rotation = rot;
			frame.TransformMatrix = mat;
			frame.Visible = true;
			frame.IsDirty = isDirty;
		}
		else
		{
			frame = new FrameTag
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

		frame.EffectiveColor = getEffectiveColor(colorTransform, frame);

		displayList[depth] = frame;

		if (!children.Any(c => c.ID == characterId))
			children.Add(new ChildInfo {
				ID = characterId,
				Type = defs.SpriteDict.ContainsKey(characterId) ? "Sprite" : "Shape"
			});

		}



	private static Color getEffectiveColor(object colorTransform = null, FrameTag frame = null)
	{
		Color finalColor = new Color(1, 1, 1, 1);

		Color baseColor = new Color(1, 1, 1, 1);

		if (colorTransform is SwfLib.Data.ColorTransformRGBA rgba)
		{
			frame.ColorTransformRGBA = rgba;

			float rMult = 1f, gMult = 1f, bMult = 1f, aMult = 1f;
			float rAdd = 0f, gAdd = 0f, bAdd = 0f, aAdd = 0f;

			if (rgba.HasMultTerms)
			{
				rMult = rgba.RedMultTerm / 255f;
				gMult = rgba.GreenMultTerm / 255f;
				bMult = rgba.BlueMultTerm / 255f;
				aMult = rgba.AlphaMultTerm / 255f;

				finalColor = new Color(
					baseColor.R * rMult ,
					baseColor.G * gMult,
					baseColor.B * bMult,
					baseColor.A * aMult 
				);
			}
			else
			{
				
				finalColor = new Color(
					baseColor.R,
					baseColor.G,
					baseColor.B,
					baseColor.A
				);

			}

			if (rgba.HasAddTerms)
			{
				rAdd = rgba.RedAddTerm / 255f;
				gAdd = rgba.GreenAddTerm / 255f;
				bAdd = rgba.BlueAddTerm / 255f;
				aAdd = rgba.AlphaAddTerm / 255f;
			}



			frame.l = (rAdd + gAdd + bAdd + aAdd)/4.0f;


		}
		else if (colorTransform is SwfLib.Data.ColorTransformRGB rgb)
		{
			frame.ColorTransform = rgb;

			float rMult = 1f, gMult = 1f, bMult = 1f;
			float rAdd = 0f, gAdd = 0f, bAdd = 0f;

			if (rgb.HasMultTerms)
			{
				rMult = rgb.RedMultTerm / 255f;
				gMult = rgb.GreenMultTerm / 255f;
				bMult = rgb.BlueMultTerm / 255f;
				finalColor = new Color(
					baseColor.R * rMult,
					baseColor.G * gMult,
					baseColor.B * bMult,
					baseColor.A
				);
			}
			else
			{
				
				finalColor = new Color(
					baseColor.R,
					baseColor.G,
					baseColor.B,
					baseColor.A
				);

			}

			if (rgb.HasAddTerms)
			{
				rAdd = rgb.RedAddTerm / 255f;
				gAdd = rgb.GreenAddTerm / 255f;
				bAdd = rgb.BlueAddTerm / 255f;
			}

			frame.l = (rAdd + gAdd + bAdd)/3.0f;

		}
		else
		{
			finalColor = baseColor;
		}


		return finalColor;
	}

	private static  bool MatrixEquals(float[] a, float[] b){
		if (a == null || b == null) return false;

		const float EPS = 0.0001f;

		for (int i = 0; i < 6; i++)
			if (Math.Abs(a[i] - b[i]) > EPS)
				return false;

		return true;
	}

	private static int ComputeSpriteDepth(int spriteID, SwfDefinitionManager defs, HashSet<int> visited = null){
		if (visited == null) visited = new HashSet<int>();
		if (visited.Contains(spriteID)) return 0;
		visited.Add(spriteID);

		if (!defs.SpriteDict.TryGetValue(spriteID, out var sprite)) return 1;

		int maxChildDepth = 0;

		foreach (var tag in sprite.Tags)
		{
			switch (tag)
			{
				case PlaceObjectTag p:
					if (defs.SpriteDict.ContainsKey(p.CharacterID))
						maxChildDepth = Math.Max(maxChildDepth, 1 + ComputeSpriteDepth(p.CharacterID, defs, new HashSet<int>(visited)));
					break;
				case PlaceObject2Tag p2:
					if (p2.HasCharacter && defs.SpriteDict.ContainsKey(p2.CharacterID))
						maxChildDepth = Math.Max(maxChildDepth, 1 + ComputeSpriteDepth(p2.CharacterID, defs, new HashSet<int>(visited)));
					break;
				case PlaceObject3Tag p3:
					if (p3.HasCharacter && defs.SpriteDict.ContainsKey(p3.CharacterID))
						maxChildDepth = Math.Max(maxChildDepth, 1 + ComputeSpriteDepth(p3.CharacterID, defs, new HashSet<int>(visited)));
					break;
			}
		}

		return maxChildDepth;
	}

   private static  FrameTag CloneFrameTag(FrameTag source){
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
			IsDirty = source.IsDirty,
			EffectiveColor = source.EffectiveColor,
			ColorTransform = source.ColorTransform,
			ColorTransformRGBA = source.ColorTransformRGBA,
			HasAnimatedColor = source.HasAnimatedColor
		};
	}

	private static Dictionary<int, Vector2> GetSpriteLocalPositions(DefineSpriteTag sprite){
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

	private static Vector2 SwfMatrixToLocal(SwfMatrix m){
		return new Vector2(m.TranslateX * 1f/20f, m.TranslateY * 1f/20f);
	}

}
