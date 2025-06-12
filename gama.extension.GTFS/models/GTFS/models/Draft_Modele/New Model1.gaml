/**
* Name: OSM file to Agents
* Author:  Patrick Taillandier
* Description: Model which shows how to import a OSM File in GAMA and use it to create Agents. In this model, a filter is done to take only into account the roads 
* and the buildings contained in the file. 
* Tags:  load_file, osm, gis
*/
model simpleOSMLoading


global
{

//map used to filter the object to build from the OSM file according to attributes. for an exhaustive list, see: http://wiki.openstreetmap.org/wiki/Map_Features
	map filtering <- map([
  "highway"::["primary", "secondary", "tertiary", "motorway", "living_street", "residential", "unclassified", "busway"],
  "railway"::["tram", "subway", "light_rail", "rail"],
  "public_transport"::["platform", "stop_position", "station"]
]);
	//OSM file to load
	file<geometry> osmfile;

	//compute the size of the environment from the envelope of the OSM file
	geometry shape <- envelope(osmfile);
	init
	{
	//possibility to load all of the attibutes of the OSM data: for an exhaustive list, see: http://wiki.openstreetmap.org/wiki/Map_Features
		create 	osm_agent from: osmfile with: [
  				highway_str::string(read("highway")),
  				railway_str::string(read("railway")),
  				public_transport_str::string(read("public_transport"))
		];


		//from the created generic agents, creation of the selected agents
ask osm_agent {
  if (length(shape.points) = 1 and (highway_str != nil or railway_str != nil)) {
    // Les points pour busway, tram, rail, subway : rarement utilisés
    create node_agent with: [
      shape::shape,
      type:: (highway_str != nil) ? highway_str : railway_str
    ];
  } else if (highway_str != nil) {
    create road with: [
      shape::shape,
      type::highway_str
    ];
  } else if (railway_str != nil) {
    create road with: [
      shape::shape,
      type::railway_str
    ];
  }
  do die;
}


	}

}

species osm_agent {
  string highway_str;
  string railway_str;
  string public_transport_str;
}


species road
{
	rgb color <- rnd_color(255);
	string type;
	aspect default
	{
		draw shape color: color;
	}

}

species node_agent
{
	string type;
	aspect default
	{
		draw square(3) color: # red;
	}

}

species building
{
	aspect default
	{
		draw shape color: #grey;
	}

}

experiment "Load OSM" type: gui
{
	parameter "File:" var: osmfile <- file<geometry> (osm_file("../../includes/rouen.gz", filtering));
	output
	{
		display map type: 3d
		{
			species building refresh: false;
			species road refresh: false;
			species node_agent refresh: false;
		}

	}

}

