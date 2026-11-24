
using Godot;

public partial class TrashPileGenerator : Node3D
{
	[ExportGroup("Trash Settings")]
	[Export] public Godot.Collections.Array<PackedScene> TrashScenes { get; set; } = new();

	[Export] public int TrashCount { get; set; } = 70;

	[ExportGroup("Pile Shape")]
	[Export] public float PileRadius { get; set; } = 0.5f;

	[Export]public float PileHeight { get; set; } = 10.0f;

	[Export] public float SpawnHeight { get; set; } = 10.0f;

	[ExportGroup("Randomization")]
	[Export] public float MinScale { get; set; } = 0.0f;

	[Export] public float MaxScale { get; set; } = 0.0f;

	private RandomNumberGenerator rng = new();

	public override void _Ready()
	{
		rng.Randomize();

		GD.Print("Trash generator started!");

		GeneratePile();
	}

	public void GeneratePile()
	{
		GD.Print("GeneratePile() called!");

		if (TrashScenes == null || TrashScenes.Count == 0)
		{
			GD.PushWarning("No trash scenes assigned in Inspector!");
			return;
		}

		GD.Print("Trash scenes assigned: ", TrashScenes.Count);

		for (int i = 0; i < TrashCount; i++)
		{
			int randomIndex = rng.RandiRange(0, TrashScenes.Count - 1);

			PackedScene selectedScene = TrashScenes[randomIndex];

			if (selectedScene == null)
			{
				GD.PushWarning($"Trash scene at index {randomIndex} is NULL!");
				continue;
			}

			Node3D trash = selectedScene.Instantiate<Node3D>();

			if (trash == null)
			{
				GD.PushWarning("Trash scene root must inherit Node3D!");
				continue;
			}

			AddChild(trash);

			float angle = rng.RandfRange(0, Mathf.Tau);
			float distance = Mathf.Sqrt(rng.Randf()) * PileRadius;

			float x = Mathf.Cos(angle) * distance;
			float z = Mathf.Sin(angle) * distance;

			float heightFactor = 1.0f -
				(distance / Mathf.Max(PileRadius, 0.001f));

			float y = rng.RandfRange(0.3f, SpawnHeight)
				+ heightFactor * PileHeight;

			trash.Position = new Vector3(x, y, z);

			trash.Rotation = new Vector3(
				rng.RandfRange(-Mathf.Pi, Mathf.Pi),
				rng.RandfRange(-Mathf.Pi, Mathf.Pi),
				rng.RandfRange(-Mathf.Pi, Mathf.Pi)
			);

			float scale = rng.RandfRange(MinScale, MaxScale);
			trash.Scale = Vector3.One * scale;
		}

		GD.Print($"Successfully spawned {TrashCount} trash objects!");
	}
}
