# Serving over ssh and telnet

`Cauldron2D.Drafter.Server` serves a game's terminal client to players who are not on this
machine. Over ssh it carries accounts, a sound port per player, the game's web endpoint and
a beacon; over telnet it carries none of them.

```elixir
{:ok, server} =
  Cauldron2D.Drafter.Server.start(
    game: Walk.Client,
    port: 2222,
    web: {:walk, Walk.Web.Endpoint, 2280}
  )

Cauldron2D.Drafter.Server.stop(server)
```

`start/1` registers the surface widget, starts the accounts store, starts drafter's ssh
daemon on `Cauldron2D.Drafter.Client`, starts the web endpoint when it is given one, and
announces the server on the local network. It answers `{:ok, server}` with a map of
`daemon`, `port`, `accounts`, `http`, `node`, `beacon` and `web`, or `{:error, reason}`.

`stop/1` closes the ssh listener first, so the port can be served on again at once, then
stops the endpoint and the beacon and disconnects each player from a process of its own,
with `notice` shown on their terminal. `stop/2` takes that notice; it defaults to
`"The server closed this session."`.

The worlds are the game's own. Register them with `Cauldron.Worlds` before or after the
server starts.

## Options

| Option | Holds | Default |
| --- | --- | --- |
| `:game` | The `Cauldron.Client.Game` module. Required | — |
| `:port` | The ssh port, `0` for any free one | `2222` |
| `:ip` | What to bind, as `Drafter.Server.start_ssh/2` takes it | `:any` |
| `:accounts` | The account file, or a running `Drafter.Accounts` server | The game's data directory |
| `:accounts_name` | A name for the accounts server it starts | None |
| `:sound_port` | The first account's sound port, `false` for none | `24_713` |
| `:system_dir` | The directory holding the ssh host keys | drafter's user data directory |
| `:register_as` | The username that registers | `"new"` |
| `:mount_props` | Merged into every session's mount props | `%{}` |
| `:send_buffer` | Bytes of each connection's send buffer | `65_536` |
| `:login_timeout` | Milliseconds a player has to log in | `600_000` |
| `:web` | `{otp_app, endpoint, port}`, the game's Phoenix endpoint | None |
| `:beacon` | Call on the local network with `Cauldron.Beacon` | `true` |
| `:beacon_port` | Its port | `Cauldron.Beacon.port/0` |
| `:node` | Name this VM so other nodes can join its worlds, `false` for none | `<atlas>@<host>` |

`:send_buffer` is the bytes of each connection's send buffer. Output beyond it waits, so a
session that draws faster than its connection carries skips frames instead of falling
behind. `:login_timeout` covers everything from connecting to logging in — ssh's host key
question and the password included.

Players connect with any ssh client:

```
ssh -p 2222 alice@arcade.example.com
```

## Accounts and passwords

Accounts are `Drafter.Accounts`'s: a file of one Erlang term per account, passwords kept as
PBKDF2-HMAC-SHA256 hashes with a random salt, never as text. A username is 1 to 32
characters from `A-Z`, `a-z`, `0-9`, `_` and `-`; a password is at least 8 characters. Five
failures from one peer in fifteen minutes are refused until the window passes.

The file is read from `Cauldron.Paths.data(home, "accounts.terms")`, `home` the game's
`Cauldron.Client.Game.home/1`, or from the same name under the game's atlas name where a
file is kept there and none under the home. A file that does not exist yet is started with
no accounts, and is written on the first change.

New players register by logging in as `new@host`:

```
ssh -p 2222 new@arcade.example.com
```

Any password opens the registration form; the account it makes logs in normally from then
on. `:register_as` changes the name. A game with accounts of its own passes them as
`:accounts` — a running `Drafter.Accounts` server, which the sessions use for logins and for
the settings they save.

Each account's props are the application's. The server gives every account a sound port
there and merges `:mount_props` into every session, so a session's props hold `:game`,
`:accounts`, `:served_by` — the host and port players were told to connect to — and
whatever else the game put there.

## Sound over a session

Sound leaves the server as raw PCM and arrives through the player's own ssh connection.
Each account's number gives it a port: the first is `:sound_port`, the next is one more,
and so on. It is kept in the account's props as `:pulse_port`.

A session served over ssh whose props carry an integer `:pulse_port` plays through
`{TuningFork.Sink.Tcp, port: pulse_port}` by default, which writes signed 16-bit
little-endian PCM to `127.0.0.1:<pulse_port>` on the server. The player's `ssh -R` tunnel
is what listens on that port and carries it to their machine:

```
ssh -p 2222 -R 24713:127.0.0.1:4713 alice@arcade.example.com
mix tuning_fork.listen --port 4713
```

The second command runs on the player's machine; `mix tuning_fork.listen` plays the PCM that
arrives through the speaker, and any program that reads raw PCM from a socket does as well,
such as `pacat --raw` or `ffplay` with `-f s16le`. The task ships with `tuning_fork_speaker`,
the package a game adds to hear sound on its own machine. `24713` is the account's port when
it is the first account made. A session without a `:pulse_port` — an account started with
`sound_port: false` — plays nothing.

`:mute` still wins over all of this: a muted session plays nothing, whatever its account's
port. `CAULDRON_MUTE`, and the game's saved launcher value when the prop is not given, do
the same. A game that plays its sessions through a sink of its own gives one with `:sink`
in `:mount_props`, or with its `sink/1`, and the tunnel is not used.

## The beacon

With `:beacon` on, the server calls `Cauldron.Beacon` every two seconds on the local
network, on UDP port `Cauldron.Beacon.port/0` — `config :cauldron_core, beacon_port: n`,
`2299` otherwise — to the broadcast address and to this machine. A call is one line:

```
cauldron 1 <game> <host> <http url or -> <node or ->
```

`<game>` is the game's atlas name, so only players of the same game hear it.
`Cauldron.Beacon.Listener` on a player's machine keeps what it heard in the last six
seconds, which is how a game presents a list of servers on the local network. A node is
joined with its cookie, which the host shows and the caller types; it never goes over the
air.

`:beacon_port` picks another port. `beacon: false` calls nothing.

## Host keys

The daemon needs a host key, and clients see it. With no `:system_dir` the key is generated
in Erlang on first use and kept in drafter's user data directory's `ssh` directory —
`:filename.basedir(:user_data, "drafter")`, which is `~/.local/share/drafter/ssh` or
`$XDG_DATA_HOME/drafter/ssh` on Linux, `~/Library/Application Support/drafter/ssh` on
macOS, and `%LOCALAPPDATA%\drafter\ssh` on Windows. The key survives restarts, so a
returning player's ssh client does not warn again. A key left in the earlier
`drafter_ssh` temporary directory is copied there.

To use keys of your own:

```
ssh-keygen -t rsa -b 2048 -f /etc/my_game/ssh_host_rsa_key -N ""
```

```elixir
{:ok, server} =
  Cauldron2D.Drafter.Server.start(game: Walk.Client, port: 2222, system_dir: "/etc/my_game")
```

`:system_dir` is passed through to `Drafter.Server.start_ssh/2`, which holds the option's
full description.

## Naming the node

With `:beacon` on and `:node` not `false`, the server names the VM `<atlas>@<host>` when the
VM is not already named, starting `epmd` first, and puts that name in the beacon's call and
in the returned map. Other nodes can then join its worlds, with the cookie the host shows.
`node: false` leaves the VM unnamed and the call's node field empty; a VM named before the
server starts keeps its own name.

## Telnet

`start_telnet/2` serves the client with no accounts and no sound: every connection runs the
terminal client on its own.

```elixir
{:ok, _listener} = Cauldron2D.Drafter.Server.start_telnet(Walk.Client, port: 2323)
```

| Option | Holds | Default |
| --- | --- | --- |
| `:port` | The TCP port, on every interface | `2323` |
| `:props` | More mount props for every session | `%{}` |

The sessions are the client's own — `game` and `mute: true` are set, and the game's
`:username` and `:settings` may be given in `:props`. Telnet carries no authentication and
no encryption, so a player is whoever they say they are and anyone on the way can read the
session. Serve it where that is acceptable: a trusted network, a test, a demonstration.

`start_telnet/2` returns `{:ok, listener}`; the socket is opened inside the acceptor
process, so a port already in use surfaces as an exit from that process.

## What an operator opens

| Port | Protocol | When |
| --- | --- | --- |
| `:port`, `2222` by default | TCP | Always, for the ssh daemon |
| `:web`'s port, `2280` in the example | TCP | When `:web` is given; the endpoint binds every IPv4 interface |
| `2323` by default | TCP | With `start_telnet/2`, on every interface |
| `2299`, or `:beacon_port` | UDP | Outbound, for the beacon's broadcast; only needed to be found on the local network |
| `4369`, and the VM's distribution port | TCP | When `:node` is on and other nodes join its worlds |

The sound ports are not opened. The server writes to `127.0.0.1:<pulse_port>` and the ssh
tunnel carries it to the player, so the traffic is inside the ssh connection. Nothing needs
forwarding for a player who does not want sound either.

## Where to go next

| You want to | Read |
| --- | --- |
| Run the client on this machine first | [Running a game in a terminal](terminal.html) |
| Understand the accounts file | `Drafter.Accounts` |
| The ssh daemon's own options | [drafter's Remote TUI guide](https://hexdocs.pm/drafter/remote_tui.html) |
| The beacon's call and its listener | `Cauldron.Beacon` and `Cauldron.Beacon.Listener` |
| Serve a browser instead | [`cauldron_2d_net`'s guide](https://hexdocs.pm/cauldron_2d_net/browser.html) |
