<section class="colophon">
<img class="colophon-mark" src="assets/cauldron-logo.png" alt="">

<h1>Cauldron</h1>

Cauldron is a game engine for the BEAM, written in Elixir.

A game is two modules. The world module is pure state and pure rules: it holds the game,
takes a tick, and answers with a view. The client module says what that view looks like —
the pictures, the keys, the menus, the sound — and every front end reads it. Because the
world is pure, a test runs a game with no process and no clock, and the same game runs in
a terminal, in a browser, in a desktop window and on a phone without being rewritten.

A game can begin as a grid of tiles, gather an atlas of art, and end as an open world of
cells streamed around the player. The contract between the game and the engine does not
change along the way.

<p class="colophon-note">This edition is generated from the guides that ship with the
packages, the same text as their documentation. The chapters follow the order a game is
built, and every link between them is a link inside this book. The figures are drawn by
the engine itself or by the examples, and each says where it comes from.</p>

<p class="colophon-note">The <code>cauldron_*</code> packages are free software under the
GNU Affero General Public License, version 3; a game or service whose source you do not
publish needs a commercial licence. The components they are built with —
<code>drafter</code>, <code>linocut</code>, <code>quake_c</code>, <code>french_curve</code>,
<code>tuning_fork</code> and <code>gamepad</code> — are MIT.</p>
</section>
