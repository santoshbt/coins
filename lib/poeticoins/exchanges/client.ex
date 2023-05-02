defmodule Poeticoins.Exchanges.Client do
  use GenServer

  @type t :: %__MODULE__{
    module: module(),
    conn: pid(),
    conn_ref: reference(),
    currency_pairs: [String.t()]
  }

  @callback exchange_name() :: String.t()
  @callback server_host :: list()
  @callback server_port :: integer()
  @callback subscription_frames([String.t()]) :: [{:text, String.t()}]
  @callback handle_ws_message(map(), t()) :: any()

  defstruct [:module, :conn, :conn_ref, :currency_pairs]
  def start_link(module, currency_pairs, options \\[]) do
    GenServer.start_link(__MODULE__, {module, currency_pairs}, options)
  end

  def init({module, currency_pairs}) do
    client = %__MODULE__{
      module: module,
      currency_pairs: currency_pairs
    }

    {:ok, client, {:continue, :connect}}
  end

  def handle_continue(:connect, state) do
    {:noreply, connect(state)}
  end

  def conn_opts do
    %{
      protocols: [:http],
      transport: :tls,
      transport_opts: [
        verify: :verify_peer,
        cacertfile: :certifi.cacertfile(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    }
  end

  def connect(client) do
    host = server_host(client.module)
    port = server_port(client.module)
    {:ok, conn} = :gun.open(host, port, conn_opts())
    conn_ref = Process.monitor(conn)
    %{client | conn: conn, conn_ref: conn_ref}
  end

  def handle_info({:gun_up, conn, :http}, %{conn: conn} = client) do
    :gun.ws_upgrade(conn, "/")
    {:noreply, client}
  end

  def handle_info({:gun_upgrade, conn, _ref, ["websocket"], _headers},
                  %{conn: conn} = client) do
    subscribe(client)
    {:noreply, client}
  end

  def handle_info({:gun_ws, conn, _ref, {:text, msg}=_frame}, %{conn: conn}=client) do
    handle_ws_message(Jason.decode!(msg), client)
  end

  def subscribe(client) do
    subscription_frames(client.module, client.currency_pairs)
    |> Enum.each(&:gun.ws_send(client.conn, &1))
  end

  @spec validate_required(map(), [String.t()]) :: :ok | {:error, {String.t(), :required}}
  def validate_required(msg, keys) do
    required_key = Enum.find(keys, fn k -> is_nil(msg[k]) end)

    if is_nil(required_key), do: :ok,
    else: {:error, {required_key, :required}}
  end

  defp subscription_frames(module, currency_pairs) do
    module.subscription_frames(currency_pairs)
  end

  defp server_host(module), do: module.server_host()

  defp server_port(module), do: module.server_port()

  defp handle_ws_message(msg, client) do
    module = client.module
    module.handle_ws_message(msg, client)
  end

end