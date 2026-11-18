defmodule Cauldron2D.Assets.Build do
  @moduledoc """
  Makes a game's art from its manifest: asks the Studio for every asset whose spec is new
  or changed, waits for the pictures, finishes each candidate as pixel art, writes a
  sheet of the candidates to choose from, and writes the chosen one into the art
  directory.

      Cauldron2D.Assets.Build.run("assets.exs", out: "priv/art")

  An asset asked for one candidate has it chosen at once. One asked for more waits for a
  choice, and so do the edits and animations made from it (`mix cauldron.assets.pick`), and its sheet is `<out>/.candidates/<name>.png`,
  the candidates left to right from `0`.

  Each request is a Studio job labelled `assets-<name>-<digest>`. A build that finds a
  queued, running or finished job under its label waits for or uses that job instead of
  asking again, so a build stopped part way, or a machine that went down, costs no work
  the Studio already has. `:again` always asks afresh. A job is waited for in rounds of
  ten minutes until it ends.

  ## Options

    * `:out` — the art directory. Default `"priv/art"`
    * `:only` — asset names to build, atoms, or strings in which `*` stands for any run of
      characters (`"hero_*"`); the rest are left as they are. Default all
    * `:again` — asset names to ask for afresh, with new seeds, even when their spec is
      unchanged. Default none
    * `:studio` — the module that calls the Studio, `Cauldron2D.Assets.Studio` by default
    * `:log` — a function given each line of progress. Default `IO.puts/1`
  """

  alias Cauldron2D.Assets.{Frames, Lock, Manifest, Sheet, Spec, Studio}
  alias FrenchCurve.Raster

  @live ["queued", "running", "done"]
  @wait_seconds 600

  @doc "Build the manifest at `path`; answers the lock it leaves, or why it stopped."
  @spec run(Path.t(), keyword()) :: {:ok, Lock.t()} | {:error, term()}
  def run(path, opts \\ []) do
    lock_path = lock_path(path)

    with {:ok, manifest} <- Manifest.load(path) do
      context = context(manifest, opts)

      manifest.specs
      |> Enum.filter(&wanted?(&1, opts[:only]))
      |> Enum.reduce_while({:ok, Lock.read(lock_path)}, fn spec, {:ok, lock} ->
        step(spec, lock, lock_path, context)
      end)
    end
  end

  defp step(spec, lock, lock_path, context) do
    case build(spec, lock, context) do
      {:ok, lock} ->
        Lock.write(lock_path, lock)
        {:cont, {:ok, lock}}

      {:error, {:not_picked, from}} ->
        context.log.("#{spec.name}: waits for #{from} to be chosen")
        {:cont, {:ok, lock}}

      {:error, reason} ->
        {:halt, {:error, {spec.name, reason}}}
    end
  end

  @doc "The lock file kept beside the manifest at `path`."
  @spec lock_path(Path.t()) :: Path.t()
  def lock_path(path), do: Path.join(Path.dirname(path), "assets.lock.exs")

  @doc "Write asset `name`'s chosen candidate, finished, into `out`, from the lock beside the manifest at `path`."
  @spec write_pick(Path.t(), atom(), keyword()) :: :ok | {:error, term()}
  def write_pick(path, name, opts \\ []) do
    with {:ok, manifest} <- Manifest.load(path),
         %Spec{} = spec <-
           Enum.find(manifest.specs, &(&1.name == name)) || {:error, {:no_asset, name}},
         %{pick: pick, candidates: candidates} when is_integer(pick) <-
           Map.get(Lock.read(lock_path(path)), name),
         {:ok, [finished]} <- finished(spec, [Enum.at(candidates, pick)]) do
      write(spec, finished, Keyword.get(opts, :out, "priv/art"))
    else
      {:error, reason} -> {:error, reason}
      _not_picked -> {:error, {:not_picked, name}}
    end
  end

  defp context(manifest, opts) do
    %{
      project: manifest.project,
      out: Keyword.get(opts, :out, "priv/art"),
      again: MapSet.new(Keyword.get(opts, :again, [])),
      studio: Keyword.get(opts, :studio, Studio),
      source: nil,
      log: Keyword.get(opts, :log, &IO.puts/1)
    }
  end

  defp wanted?(_spec, nil), do: true
  defp wanted?(spec, only), do: Enum.any?(only, &named?(spec.name, &1))

  defp named?(name, pattern) when is_atom(pattern), do: name == pattern

  defp named?(name, pattern) do
    expression = pattern |> String.split("*") |> Enum.map_join(".*", &Regex.escape/1)
    Regex.match?(Regex.compile!("^" <> expression <> "$"), Atom.to_string(name))
  end

  defp build(spec, lock, context) do
    with {:ok, source} <- source(spec, lock),
         digest = Spec.digest(spec, source),
         {:ok, entry} <-
           candidates(spec, Map.get(lock, spec.name), digest, %{context | source: source}),
         {:ok, finished} <- finished(spec, entry.candidates) do
      Sheet.write(Path.join([context.out, ".candidates", "#{spec.name}.png"]), finished)
      entry = chosen(entry, spec)
      write_chosen(spec, entry, finished, context)
      {:ok, Map.put(lock, spec.name, entry)}
    end
  end

  defp candidates(spec, %{digest: digest} = entry, digest, context) do
    if MapSet.member?(context.again, spec.name),
      do: ask(spec, digest, context),
      else: {:ok, entry}
  end

  defp candidates(spec, _entry, digest, context), do: ask(spec, digest, context)

  defp source(%Spec{from: nil}, _lock), do: {:ok, nil}

  defp source(%Spec{from: from}, lock) do
    case Map.get(lock, from) do
      %{pick: pick, candidates: candidates} when is_integer(pick) ->
        {:ok, Enum.at(candidates, pick).id}

      _unchosen ->
        {:error, {:not_picked, from}}
    end
  end

  defp request(spec, %{source: nil} = context),
    do: {"generate_image", Spec.request(spec, context.project)}

  defp request(%Spec{video: nil} = spec, context),
    do: {"edit_image", Spec.edit_request(spec, context.source, context.project)}

  defp request(spec, context),
    do: {"make_video", Spec.video_request(spec, context.source, context.project)}

  defp ask(%Spec{rig: rig} = spec, digest, context) when rig != nil do
    motion = {"make_motion", &Spec.motion_request(spec, &1, context.project)}
    animation = {"make_animation", &Spec.animation_request(spec, &1, context.project)}

    with {:ok, motions} <- each_job(spec, digest, "motion", seeds(spec), motion, context),
         {:ok, animations} <- each_job(spec, digest, "animation", motions, animation, context),
         {:ok, %{"items" => items}} <-
           context.studio.call("get_result", %{ids: animations, max_size: 64}) do
      {:ok, %{digest: digest, candidates: Enum.map(items, &candidate/1), pick: nil}}
    else
      {:ok, unexpected} -> {:error, {:studio, unexpected}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ask(spec, digest, context) do
    batch = "assets-#{spec.name}-#{digest}"

    with {:ok, job} <- job(spec, batch, request(spec, context), context),
         {:ok, ids} <- outcome(job, context),
         {:ok, %{"items" => items}} <-
           context.studio.call("get_result", %{ids: ids, max_size: 64}) do
      {:ok, %{digest: digest, candidates: Enum.map(items, &candidate/1), pick: nil}}
    else
      {:ok, unexpected} -> {:error, {:studio, unexpected}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp seeds(%Spec{seed: nil, count: count}),
    do: for(_candidate <- 1..count, do: :rand.uniform(4_294_967_295))

  defp seeds(%Spec{seed: seed, count: count}), do: Enum.to_list(seed..(seed + count - 1))

  defp each_job(spec, digest, stage, inputs, {tool, arguments}, context) do
    inputs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {input, index}, {:ok, ids} ->
      batch = "assets-#{spec.name}-#{digest}-#{stage}-#{index}"

      with {:ok, job} <- job(spec, batch, {tool, arguments.(input)}, context),
           {:ok, [id | _rest]} <- outcome(job, context) do
        {:cont, {:ok, ids ++ [id]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp job(spec, batch, {tool, arguments}, context) do
    with {:ok, nil} <- earlier_job(spec, batch, context) do
      context.log.("#{spec.name}: asking with #{tool} (#{batch})")

      case context.studio.call(tool, Map.put(arguments, :batch, batch)) do
        {:ok, %{"job_id" => job}} -> {:ok, job}
        {:ok, unexpected} -> {:error, {:studio, unexpected}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, job} ->
        context.log.("#{spec.name}: the Studio already has it, as job #{job}")
        {:ok, job}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp earlier_job(spec, batch, context) do
    if MapSet.member?(context.again, spec.name) do
      {:ok, nil}
    else
      case context.studio.call("list_jobs", %{batch: batch, limit: 20}) do
        {:ok, %{"jobs" => jobs}} -> {:ok, Enum.find_value(jobs, &live_job/1)}
        {:ok, unexpected} -> {:error, {:studio, unexpected}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp live_job(%{"status" => status, "job_id" => job}) when status in @live, do: job
  defp live_job(_ended), do: nil

  defp outcome(job, context) do
    case context.studio.call("wait_for_jobs", %{job_ids: [job], timeout_seconds: @wait_seconds}) do
      {:ok, %{"all_finished" => false}} -> outcome(job, context)
      {:ok, %{"result_ids" => [_ | _] = ids}} -> {:ok, ids}
      {:ok, unexpected} -> {:error, {:studio, unexpected}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp candidate(item),
    do: %{id: item["id"], path: item["path"], url: item["url"], seed: item["seed"]}

  defp finished(%Spec{rig: rig, motion: motion} = spec, candidates) when rig != nil do
    choice = if motion[:loop], do: [], else: Keyword.take(motion, [:keep, :from, :to])

    Enum.reduce_while(candidates, {:ok, []}, fn candidate, {:ok, acc} ->
      case Frames.pick(Path.join(Path.dirname(candidate.path), "frames"), choice) do
        {:ok, frames} ->
          {:cont, {:ok, acc ++ [frames |> Frames.finish(spec.finish) |> Frames.strip()]}}

        {:error, reason} ->
          {:halt, {:error, {:frames, candidate.id, reason}}}
      end
    end)
  end

  defp finished(%Spec{video: video} = spec, candidates) when video != nil do
    Enum.reduce_while(candidates, {:ok, []}, fn candidate, {:ok, acc} ->
      case Frames.extract(candidate.path, Keyword.take(video, [:keep, :from, :to])) do
        {:ok, frames} ->
          {:cont, {:ok, acc ++ [frames |> Frames.finish(spec.finish) |> Frames.strip()]}}

        {:error, reason} ->
          {:halt, {:error, {:frames, candidate.id, reason}}}
      end
    end)
  end

  defp finished(spec, candidates) do
    Enum.reduce_while(candidates, {:ok, []}, fn candidate, {:ok, acc} ->
      case picture(candidate) do
        {:ok, picture} -> {:cont, {:ok, acc ++ [Linocut.Pixelate.finish(picture, spec.finish)]}}
        {:error, reason} -> {:halt, {:error, {:picture, candidate.id, reason}}}
      end
    end)
  end

  defp picture(%{path: path, url: url}) do
    if path && File.exists?(path) do
      Linocut.load(path)
    else
      with {:ok, %{status: 200, body: bytes}} <- Req.get(url, decode_body: false),
           do: Linocut.Png.decode(bytes)
    end
  end

  defp chosen(%{pick: nil, candidates: [_only]} = entry, _spec), do: %{entry | pick: 0}
  defp chosen(entry, _spec), do: entry

  defp write_chosen(spec, %{pick: nil}, _finished, context),
    do: context.log.("#{spec.name}: choose from #{context.out}/.candidates/#{spec.name}.png")

  defp write_chosen(spec, %{pick: pick}, finished, context) do
    write(spec, Enum.at(finished, pick), context.out)
    context.log.("#{spec.name}: candidate #{pick} written")
  end

  defp write(spec, %Raster{} = raster, out) do
    File.mkdir_p!(out)
    rgba = Raster.to_rgba_binary(raster)

    File.write!(
      Path.join(out, "#{spec.name}.png"),
      FrenchCurve.Png.encode(raster.width, raster.height, rgba)
    )
  end
end
