using Toybox.Communications as Comm;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;

class HassIQState {
	var serviceCallback = null;
	var updateCallback = null;
	var state = 0;
	var entities = null;
	var selected = null;
	var host = null;
	var password = null;
	var visibilityGroup = null;

	static var on = "on";
	static var off = "off";

	function initialize() {
	}

	function setHost(host) {
		self.host = host;
	}

	function setPassword(password) {
		self.password = password;
	}

	function setGroup(group) {
		self.visibilityGroup = group;
	}

	function save() {
		if (entities == null) {
			return null;
		}

		var size = entities.size();		
		var stored = new [size];

		for (var i=0; i<size; ++i) {
			var entity = entities[i];
			stored[i] = { "entity_id" => entity[:entity_id], "name" => entity[:name], "state" => entity[:state] };
		}

		return stored;
	}

	function load(stored) {
		if (!(stored instanceof Array)) {
			return;
		}

		var size = stored.size();
		entities = new [size];

		for (var i=0; i<size; ++i) {
			var store = stored[i];
			entities[i] = { :entity_id => store["entity_id"], :name => store["name"], :state => store["state"] };
			if (entities[i][:state] != null) {
				updateEntityState(entities[i], entities[i][:state]);
			}
		}
	}

	function destroy() {
		self.updateCallback = null;
		self.serviceCallback = null;
	}

	function api() {
		return host + "/api";
	}

	function update(callback) {
		log("Requesting update");

		self.updateCallback = callback;

		Comm.makeJsonRequest(api() + "/states/" + visibilityGroup, null,
			{ :method => Comm.HTTP_REQUEST_METHOD_GET, :headers =>
				{ "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON, "Accept" => "application/json" ,
				  "x-ha-access" => password }
			}, method(:onUpdateReceive) );

		return true;
	}

	function onUpdateReceive(responseCode, data) {
		if (responseCode == 200) {
			log("Received data:"+data);

			self.state = 1;
			var selected_id = self.selected != null ? self.selected[:entity_id] : null;
			self.selected = null;

			self.entities = buildEntities(data, entities);

			var size = entities.size();
			for (var i=0; i<size; ++i) {
				var entity = entities[i];

				if (selected_id != null && selected_id.equals(entity[:entity_id])) {
					self.selected = entity;
					break;
				}
			}

			if (size > 0) {
				singleUpdate(entities[0]);
			}
		} else {
			log("Failed to load\nError: " + responseCode.toString());
			self.state = -1;
		}

		if (self.updateCallback != null) {
			self.updateCallback.invoke(self);
		}
	}

	function singleUpdate(entity) {
		log("Fetching:"+entity[:entity_id]);

		Comm.makeJsonRequest(api() + "/states/" + entity[:entity_id], null,
			{ :method => Comm.HTTP_REQUEST_METHOD_GET, :headers =>
				{ "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON, "Accept" => "application/json" ,
				  "x-ha-access" => password }
			}, method(:onSingleUpdateReceive) );
	}

	function onSingleUpdateReceive(responseCode, data) {
		if (responseCode == 200) {
			log("Received data:"+data);

			var entity = buildEntity(data, entities);

			var size = entities.size();
			for (var i=0; i<size-1; ++i) {
				if (entity[:entity_id].equals(entities[i][:entity_id])) {
					singleUpdate(entities[i+1]);
				}
			}
		} else {
			log("Failed to load\nError: " + responseCode.toString());
		}

		if (self.updateCallback != null) {
			self.updateCallback.invoke(self);
		}
	}

	function callService(domain, service, entity, callback) {
		if(self.serviceCallback != null) {
			return false;
		}

		self.serviceCallback = callback;

		var data = {};
		if (domain != "script") {
			data = { "entity_id" => entity[:entity_id] };
		}
		Comm.makeJsonRequest(api() + "/services/" + domain + "/" + service,
			data,
			{ :method => Comm.HTTP_REQUEST_METHOD_POST, :headers =>
				{ "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON, "Accept" => "application/json",
				  "x-ha-access" => password }
			}, method(:onServiceReceive) );

		return true;
	}

	function onServiceReceive(responseCode, data) {
		if (responseCode == 200) {
			log("Received data:"+data);

			var size = data.size();
			for (var i=0; i<size; ++i) {
				buildEntity(data[i], entities);
			}
		} else {
			log("Failed to load\nError: " + responseCode.toString());
		}

		if (self.serviceCallback != null) {
			self.serviceCallback.invoke(self);
			self.serviceCallback = null;
		}
	}

	function updateEntityState(entity, state) {
		if (state == null) {
			state = entity[:state] != null ? entity[:state] : off;
		}
		var drawable = null;
		if (getEntityDomain(entity).equals("sun")) {
			if (state.equals("above_horizon") ) {
				drawable = new Ui.Bitmap({:rezId=>Rez.Drawables.sun});
			}
			else {
				drawable = new Ui.Bitmap({:rezId=>Rez.Drawables.moon});
			}
			entity[:drawable] = drawable;
		} else {
			if (state.equals(on)) {
				state = on;
			}
			else if(state.equals(off)) {
				state = off;
			}

			var title = entity[:name] ? entity[:name] : entity[:entity_id];
			var color = Gfx.COLOR_WHITE;
			if (state.equals(on)) {
				title = "* " + title;
			}
			entity[:title] = title;
			if (entity[:drawable]) {
				entity[:drawable].setText(title);
				entity[:drawable].setColor(color);
			}
			else {
				drawable = new Ui.Text({:text=>title, :font=>Gfx.FONT_TINY, :locX =>Ui.LAYOUT_HALIGN_CENTER, :locY=>0, :color=>color});
				entity[:drawable] = drawable;
			}
		}

		entity[:state] = state;
	}

	function buildEntity(item, previous) {
		var entity_id = item["entity_id"];
		var state = item["state"];
		var attributes = item["attributes"];
		var name = null;
		var hid = false;
		if (attributes != null) {
			name = attributes["friendly_name"];
			hid = attributes["hidden"];
		}

		if (hid == true) {
			return null;
		}

		var entity = null;
		if (previous != null) {
			for (var j=0; j<previous.size(); ++j) {
				if (previous[j][:entity_id].equals(entity_id)) {
					entity = previous[j];
					break;
				}
			}
		}
		if (entity == null) { entity = {:entity_id=>entity_id, :name=>name}; }
		else if (name != null) { entity[:name] = name; }

		updateEntityState(entity, state);

		return entity;
	}

	function buildEntities(data, previous) {
		var size = 0;
		var entities;
		if (data instanceof Array) {
			var entities_size = data.size();
			entities = new [entities_size];
			for (var i=0; i<entities_size; ++i) {
				var entity = buildEntity(data[i], previous);

				if (entity == null) {
					continue;
				}

				entities[size] = entity;
				size++;
			}
		}
		else {
			var entities_list = data["attributes"]["entity_id"];
			var entities_size = entities_list.size();
			entities = new [entities_size];
			for (var i=0; i<entities_size; ++i) {
				var entity = buildEntity({"entity_id" => entities_list[i]}, previous);

				if (entity == null) {
					continue;
				}

				entities[size] = entity;
				size++;
			}
		}

		var sorted = new [size];
		var s = 0;
		for (var p=0; p<2; ++p) {
			for (var i=0; i<size; ++i) {
				var entity = entities[i];
				var domain = getEntityDomain(entity);
				if (domain.equals("sun")) {
					if (p == 0) {
						sorted[s] = entity;
						s++;
					}
				}
				else {
					if (p == 1) {
						sorted[s] = entity;
						s++;
					}
				}
			}
		}
		return sorted;
	}

	function getEntityDomain(entity) {
		var entity_id = entity[:entity_id] ? entity[:entity_id] : entity["entity_id"];
		return split(entity_id, ".")[0];
	}

	function getEntityId(entity) {
		var entity_id = entity[:entity_id] ? entity[:entity_id] : entity["entity_id"];
		return split(entity_id, ".")[1];
	}

	function split(s, sep) {
		var tokens = [];

		var found = s.find(sep);
		while (found != null) {
			var token = s.substring(0, found);
			tokens.add(token);
			s = s.substring(found + sep.length(), s.length());
			found = s.find(sep);
		}

		tokens.add(s);

		return tokens;
	}

	function inArray(a, item) {
		var size = a.size();
		for (var i=0; i<size; ++i) {
			if (a[i].equals(item)) {
				return true;
			}
		}
		return false;
	}

	function log(message) {
		System.println(message);
	}

	(:test)
	function assert(condition) { if(!condition) { oh_no(); }}
	(:test)
	function test_buildEntities(logger) {
		var data = [
			{
				"attributes" => {
					"hidden" => true,
					"friendly_name" => "item1"
				},
				"entity_id" => "test.item1"
			},
			{
				"attributes" => {
					"friendly_name" => "item2"
				},
				"entity_id" => "test.item2"
			}
		];

		var entities = buildEntities(data, null);
		assert(entities.size() == 1);
		assert(getEntityDomain(entities[0]).equals("test"));
	}
}
