# Waves

A GPU simulation of three-dimensional incompressible free-surface flow in Godot, focused on the shoaling and breaking of waves over a sloping beach. The liquid is represented volumetrically, allowing crest overturning, an overhanging lip, impact, runup and backwash, with an air cavity beneath the curling wave.

## Demonstration

<!-- Replace VIDEO_URL_HERE with the uploaded video's URL on its own line. -->

[VIDEO_URL_HERE](https://private-user-images.githubusercontent.com/333056031/691592819-381c4c12-9354-46a4-a1e5-dd363d65ad63.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3OTM1NTk1NjcsIm5iZiI6MTc5MzU1OTI2NywicGF0aCI6Ii8zMzMwNTYwMzEvNjkxNTkyODE5LTM4MWM0YzEyLTkzNTQtNDZhNC1hMWU1LWRkMzYzZDY1YWQ2My5tcDQ_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjYxMTAxJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI2MTEwMVQxODU0MjdaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT0xODY2MTgyMDkwMDdjOTM2MTNkZTgyOTMyOTVjYTE2NzQ4N2JjZjFjYjMwZDYxMWQ0MDlkMTZlMDZmNzliYWYzJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCZyZXNwb25zZS1jb250ZW50LXR5cGU9dmlkZW8lMkZtcDQifQ.GrOZE3N5px_TRdP0Pp_NVNgM76u8A6ytec_IO8OILeQ)

*Full-width reference simulation rendered offline with the current water material. Playback follows simulated physical time.*

## Numerical method and research basis

The interface-transport formulation follows the conservative volume-of-fluid (VOF) framework of Weymouth and Yue [1]. Each grid cell stores a liquid volume fraction, `F`, between zero and one. Piecewise-linear interface reconstruction (PLIC) estimates the liquid boundary within partially filled cells, and geometric fluxes transport liquid between neighbouring cells.

The underlying transport and incompressibility conditions are

$$
\frac{\partial F}{\partial t} + \nabla \cdot (F\mathbf{u}) = 0,
\qquad
\nabla \cdot \mathbf{u} = 0,
$$

where `u` is the velocity field. Wave forcing and boundary exchange are handled separately from interior transport.

The solver combines this interface representation with:

- A staggered marker-and-cell (MAC) grid, with velocity components stored on cell faces.
- Limited semi-Lagrangian MacCormack velocity advection, following Selle et al. [2].
- A multigrid-preconditioned conjugate-gradient pressure solve to enforce discrete incompressibility.
- CFL-controlled substeps, numerical acceptance checks and rollback.

Simulation kernels run on the GPU through Godot's compute pipeline. The visible surface is reconstructed from the liquid volume, including the underside of an overturning crest.

The project was also informed by Braun et al.'s ST-FLIP research [3], which studies spatiotemporal particle-grid transfer for liquid simulation with large timesteps. That work provided a reference for the breaking-wave behaviour explored here; the solver distributed in this repository uses geometric VOF.

## Beach configuration

The default scene is a 4 m-wide beach. The x, y and z axes correspond to the cross-shore, vertical and alongshore directions.

| Setting | Value |
| --- | --- |
| Domain, x × y × z | 7.75 × 1.20 × 4.00 m |
| Grid | 310 × 48 × 80 cells |
| Total grid cells | 1,190,400 |
| Cell spacing | 0.025 × 0.025 × 0.050 m |
| Offshore water depth | 0.45 m |
| Beach slope | 1:6 |
| Incoming wave amplitude | 0.08 m |
| Incoming wave period | 1.4 s |
| Forcing ramp | 4 wave periods, or 5.6 s |

Allow several **simulation seconds** for the incoming waves to develop and reach the beach.

## Appearance

The scene opens paused in **Water** mode, with turquoise water, reflections, shallow-water transparency and a smooth sand surface. **Clay** mode displays the same simulated geometry with diagnostic shading.

Optical thickness is evaluated through occupied liquid intervals. Air gaps beneath the crest are excluded from the water's absorption path. The visible sand mesh follows the continuous beach profile; fluid collisions retain the solver's cell-based representation of the bed.

In Water mode, **Transmission distance** controls the distance over which light is attenuated. Shorter distances produce stronger body colour and less seabed visibility; longer distances make the water clearer. The default is **0.18 m**. **Water colour** changes the tint.

Surface ripple animation follows accepted simulation time and freezes when the simulation is paused.

## Run

Requires **Godot 4.7.2 with Forward+/Vulkan** and a Vulkan-capable GPU with compute support. Use the standard Godot build; .NET is not required. The Compatibility renderer is not supported.

No addons, native extensions or external asset downloads are needed. Godot generates its import cache when the project is first opened.

### Godot editor

1. Import `project.godot` in the Godot Project Manager.
2. Open the project and let the initial shader import finish.
3. Press **F5** to run, then **Space** to start the waves.

### Windows launcher

Make a Godot executable available on `PATH` as `godot.exe`, `godot4.exe`, `godot_console.exe` or `godot4_console.exe`. Alternatively, set `GODOT_EXE` to the full path of the Godot executable.

From PowerShell in this folder:

```powershell
.\launch.bat
```

You can also double-click `launch.bat` when the engine is available through your environment. The launcher resolves the project from its own location, including paths containing spaces.

## Controls

| Input | Action |
| --- | --- |
| **Space** | Run / pause |
| **N** | Advance one solver step while paused |
| **R** | Reset the simulation and pause |
| **1** | Elevated showcase camera |
| **2** | Side camera for inspecting the curl |
| **Right mouse drag** | Orbit the camera |
| **Mouse wheel** | Zoom |
| **F2** or **Water / Clay** button | Switch appearance without resetting the simulation |
| **F3** | Show / hide the status and help text |

Pausing lets already submitted GPU work finish before the state settles. Appearance controls remain visible when the status text is hidden.

## Scope and performance

The physical model treats water as a single incompressible liquid phase with atmospheric pressure outside it. Enclosed air cavities are represented geometrically; air motion and trapped-air compression are not solved. Thin sheets and small-scale breakup are limited by the grid resolution.

The full-width calculation can advance more slowly than real time. The on-screen simulation clock reports accepted physical progress; rendering frame rate measures presentation, not the rate of simulated time. Numerical acceptance checks and rollback remain active during execution.

The demonstration video uses offline capture so that playback can follow physical simulation time.

## Project layout

- `project.godot` and `water_lab.tscn`: project settings and entry scene.
- `water/`: simulation orchestration, pressure solver and interaction controls.
- `water/shaders/compute/`: GPU fluid simulation kernels and shared mathematics.
- `water/presentation/`: water appearance, daylight, procedural sand and presentation controls.
- `water/shaders/render/`: diagnostic Clay rendering.
- `launch.bat`: portable Windows launcher.

Keep the supplied `.uid` and `.import` files with their resources. The generated `.godot/` directory is local cache data and is excluded from Git.

## References

1. **G. D. Weymouth and D. K.-P. Yue (2010).** [Conservative Volume-of-Fluid method for free-surface simulations on Cartesian-grids](https://doi.org/10.1016/j.jcp.2009.12.018). *Journal of Computational Physics*, 229(8), 2853–2865. Interface reconstruction and conservative liquid-volume transport.

2. **A. Selle, R. Fedkiw, B.-M. Kim, Y. Liu and J. Rossignac (2008).** [An Unconditionally Stable MacCormack Method](https://andyselle.com/papers/7/). *Journal of Scientific Computing*, 35, 350–371. Velocity-advection reference; the complete fluid solver retains its CFL restrictions.

3. **B. Braun, R. Winchenbach, J. Bender and N. Thuerey (2026).** [Spatiotemporal FLIP for Fast Free-Surface and Two-Phase Simulation With Very Large Time Steps](https://doi.org/10.1145/3811289). *ACM Transactions on Graphics*, 45(4), Article 76. Related work and a reference for detailed breaking-wave simulation.
