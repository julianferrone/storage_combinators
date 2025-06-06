defmodule Matryoshka.Impl.MappingStore do
  alias Matryoshka.IsStorage

  @identity &Function.identity/1

  @enforce_keys [:inner]
  defstruct [
    :inner,
    map_ref: @identity,
    map_retrieved: @identity,
    map_to_store: @identity
  ]

  @type t :: %__MODULE__{
          inner: IsStorage.t(),
          map_ref: (Matryoshka.Reference -> Matryoshka.Reference),
          map_retrieved: (any() -> any()),
          map_to_store: (any() -> any())
        }


  @doc """
  Wraps an inner store with a mapping layer.

  The `mapping_store/2` function allows you to map values when reading from
  or writing to the `inner` store. It accepts an `inner` store and an optional
  list of options.

  ## Parameters

  * `inner` - The underlying store module or instance to wrap. Must implement
    the `Matryoshka.Storage` protocol.
  * `opts` - (keyword list) Optional settings:

    * `:map_to_store` - (function) A function `(value -> stored_value)` that
      maps values *before* storing them. Defaults to `Function.identity/1`.
    * `:map_retrieved` - (function) A function `(stored_value -> value)` that
      maps values when retrieved (get/fetch) from the store. Defaults to
      `Function.identity/1`.
    * `:map_ref` - (function). A function that maps references
      `(ref -> mapped_ref)` before using them to locate values. Defaults to
      `Function.identity/1`.

  If the mapping function aren't provided, values and references are passed
  through unchanged.

  ## Examples:

  Imports:

      iex> alias Matryoshka.Storage
      iex> alias Matryoshka.Impl.MapStore
      iex> alias Matryoshka.Impl.MappingStore

  Mapping value with function when putting the value:

      iex> store = MapStore.map_store() |> MappingStore.mapping_store(
      ...>   [map_to_store: fn x -> x + 1 end]
      ...> )
      iex> store = Storage.put(store, "one", 1)
      iex> {_store, value} = Storage.get(store, "one")
      iex> value
      2

  Mapping value with function when retrieving (get/fetch) the value:

      iex> store = MapStore.map_store() |> MappingStore.mapping_store(
      ...>   [map_retrieved: fn x -> x - 1 end]
      ...> )
      iex> store = Storage.put(store, "one", 1)
      iex> {_store, value} = Storage.get(store, "one")
      iex> value
      0

  Mapping reference with function:

      iex> store = MapStore.map_store() |> MappingStore.mapping_store(
      ...>   [map_ref: fn x -> Atom.to_string(x) end]
      ...> )
      iex> store = Storage.put(store, :item, "item")
      iex> {_store, value} = Storage.get(store, :item)
      iex> value
      "item"
  """
  def mapping_store(inner, opts \\ []) do
    IsStorage.is_storage!(inner)
    map_ref = Keyword.get(opts, :map_ref, @identity)
    map_retrieved = Keyword.get(opts, :map_retrieved, @identity)
    map_to_store = Keyword.get(opts, :map_to_store, @identity)

    %__MODULE__{
      inner: inner,
      map_ref: map_ref,
      map_retrieved: map_retrieved,
      map_to_store: map_to_store
    }
  end

  alias __MODULE__

  defimpl Matryoshka.Storage do
    @spec fetch(MappingStore.t(), Matryoshka.Reference) :: any()
    def fetch(store, ref) do
      {inner_new, value} =
        Matryoshka.Storage.fetch(
          store.inner,
          store.map_ref.(ref)
        )

      store_new = %{store | inner: inner_new}

      value_new =
        case value do
          {:ok, value} -> {:ok, store.map_retrieved.(value)}
          error -> error
        end

      {store_new, value_new}
    end

    def get(store, ref) do
      {inner_new, value} = Matryoshka.Storage.get(store.inner, store.map_ref.(ref))

      store_new = %{store | inner: inner_new}

      value_new =
        case value do
          nil -> nil
          value -> store.map_retrieved.(value)
        end

      {store_new, value_new}
    end

    def put(store, ref, value) do
      inner_new =
        Matryoshka.Storage.put(
          store.inner,
          store.map_ref.(ref),
          store.map_to_store.(value)
        )

      %{store | inner: inner_new}
    end

    def delete(store, ref) do
      inner_new = Matryoshka.Storage.delete(store.inner, store.map_ref.(ref))
      %{store | inner: inner_new}
    end
  end
end
