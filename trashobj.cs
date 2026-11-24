
using Godot;

[GlobalClass]
public partial class TrashObject : RigidBody3D
{
	[Export]
	public string ItemId = "unknown";

	[Export]
	public float CollectionValue = 1.0f;

	public override void _Ready()
	{
		CanSleep = true;
	}
}
