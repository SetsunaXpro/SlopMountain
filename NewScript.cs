using Godot;

public partial class Player : CharacterBody3D
{
	private const float Speed = 5.0f;
	private const float JumpVelocity = 4.5f;

	private float _gravity = 9.8f;

	public override void _PhysicsProcess(double delta)
	{
		Vector3 velocity = Velocity;

		// Apply gravity
		if (!IsOnFloor())
		{
			velocity.Y -= _gravity * (float)delta;
		}

		// Jump using Space
		if (Input.IsActionJustPressed("ui_accept") && IsOnFloor())
		{
			velocity.Y = JumpVelocity;
		}

		// WASD / Arrow key movement
		Vector2 inputDir = Input.GetVector(
			"ui_left",
			"ui_right",
			"ui_up",
            "ui_down"
		);

		Vector3 direction = new Vector3(
			inputDir.X,
			0,
			inputDir.Y
		);

		if (direction != Vector3.Zero)
		{
			velocity.X = direction.X * Speed;
			velocity.Z = direction.Z * Speed;
		}
		else
		{
			velocity.X = Mathf.MoveToward(velocity.X, 0, Speed);
			velocity.Z = Mathf.MoveToward(velocity.Z, 0, Speed);
		}

		Velocity = velocity;
		MoveAndSlide();
	}
}
