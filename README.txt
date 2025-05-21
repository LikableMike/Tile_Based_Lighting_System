Some things of note:
Take a look at the image provided. notice the MapShadows sprite as a child of the player. This is important as the node follows the player for rendering purposes.

The canvas modulate and the pointlight 2d under enviroment provide additional lighting effects and this is important as all my dynamic light sources also include a point light. these onyl work with the canvas modulate
The point light is just a very large gradient light to fake sunlight when above ground.

The MapShadows sprite has the Shadow.gdshader attached to its material.

