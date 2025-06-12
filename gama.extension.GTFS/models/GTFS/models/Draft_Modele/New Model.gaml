/**
* Name: generate_environment
* Author: Patrick Taillandier
* Description: Demonstrates how to import data from OSM, Bing and google map to generate geographical data. More precisely, the model allows from a shapefile giving the area of the study area to download all the OSM data on this area, to vectorize the buildings and the points of interest from google map data and to download a Bing satellite image of the area.
* Tags: data_loading, OSM, Google Map, Bing, shapefile
*/
model download_spatial_data

global {

/* ------------------------------------------------------------------ 
	 * 
	 *             MANDATORY PARAMETERS
	 * 
	 * ------------------------------------------------------------------
	 */

	//define the bounds of the studied area
	file data_file <-shape_file("../../includes/stops_points_wgs84.shp");
	
	//path where to export the created shapefiles
	string exporting_path <- "results/";
	
	//if true, GAMA is going to use OSM data to create the building file
	bool use_OSM_data <- true;
	
	
	

	//image to display as background if there is no satellite image
	string default_background_image <- "../../includes/white.png";
	
	/* ------------------------------------------------------------------ 
	 * 
	 *             OPTIONAL PARAMETERS
	 * 
	 * ------------------------------------------------------------------
	 */
	// --------------- OSM data parameters ------------------------------
	//path to an existing Open Street Map file - if not specified, GAMA is going to directly download to correct data
	string osm_file_path <- "../includes/map.osm";
	
	//type of feature considered
	map<string, list> osm_data_to_generate <- [
    // Les principaux tags OSM utilisés pour les transports publics linéaires :
    "highway"::[],       // Pour busway, cycleway, routes...
    "railway"::[],       // Tram, subway, railway, light_rail
    "route"::[],         // Les relations de transport en commun
    "cycleway"::[]       // Pistes cyclables si tu veux les lignes vélos
];

	
	//possibles colors for buildings
	list<rgb> color_bds <- [rgb(241,243,244), rgb(255,250,241)];
	


	
	
	/* ------------------------------------------------------------------ 
	 * 
	 *              DYNAMIC VARIABLES
	 * 
	 * ------------------------------------------------------------------
	 */

	//geometry of the bounds
	geometry bounds_tile;
	
	//index used to read google map tiles
	int ind <- 0;

	
	
	
	
	//geometry of the world
	geometry shape <- envelope(data_file);
	
	
	init {
		write "Start the pre-processing process";
		
		
		if use_OSM_data {
			osm_file osmfile;
			if (file_exists(osm_file_path)) {
				osmfile  <- osm_file(osm_file_path, osm_data_to_generate);
			} else {
				point top_left <- CRS_transform({0,0}, "EPSG:4326").location;
				point bottom_right <- CRS_transform({shape.width, shape.height}, "EPSG:4326").location;
				string adress <-"http://overpass-api.de/api/xapi_meta?*[bbox="+top_left.x+"," + bottom_right.y + ","+ bottom_right.x + "," + top_left.y+"]";
				write "adress: " + adress;
				osmfile <- osm_file<geometry> (adress, osm_data_to_generate);
			}
			
			write "OSM data retrieved";
			create OSM_agent from: osmfile  where (each != nil);
			loop type over: osm_data_to_generate.keys {
		 		rgb col <- rnd_color(255);
		 		list<OSM_agent> ags <-  OSM_agent where (each.shape.attributes[type] != nil);
		 		ask ags {color <- col;}
		 		list<OSM_agent> pts <- ags where (each.shape.perimeter = 0);
		 		
		 		
		 		list<OSM_agent> lines <- ags where ((each.shape.perimeter > 0) and (each.shape.area = 0)) ;
		 	
		 		
		 		list<OSM_agent> polys <- ags where (each.shape.area > 0);
		 		
		 	}
		}	 	

	 
	}
	
	

	
	action save_meta_data (string rest_link) {
		list<string> v <- string(json_file(rest_link).contents) split_with ",";
		write "Satellite image retrieved";
		int id <- 0;
		loop i from: 0 to: length(v) - 1 {
			if ("bbox" in v[i]) { 
				id <- i;
				break;
			}
		} 
		float long_min <- float(v[id] replace ("'bbox'::[",""));
		float long_max <- float(v[id+2] replace (" ",""));
		float lat_min <- float(v[id + 1] replace (" ",""));
		float lat_max <- float(v[id +3] replace ("]",""));
		point pt1 <- CRS_transform({lat_min,long_max},"EPSG:4326", "EPSG:3857").location ;
		point pt2 <- CRS_transform({lat_max,long_min},"EPSG:4326","EPSG:3857").location;
		float width <- abs(pt1.x - pt2.x)/1500;
		float height <- (pt2.y - pt1.y)/1500;
			
		string info <- ""  + width +"\n0.0\n0.0\n"+height+"\n"+min(pt1.x,pt2.x)+"\n"+(height < 0 ? max(pt1.y,pt2.y) : min(pt1.y,pt2.y));
	
		save info to: exporting_path +"satellite.pgw" format:"text";
	}
	
	
	}



species OSM_agent {
	rgb color;
	aspect default {
		if (shape.area > 0) {
			draw shape color: color border: #black;
		} else if shape.perimeter > 0 {
			draw shape color: color;
		} else {
			draw circle(5) color: color;
		}
		
	}	
}

species Boundary {
	aspect default {
		draw shape color: #gray border: #black;
	}
}

experiment downloadGISdata type: gui autorun: true{

	output {
		display map type: 3d axes: false{
			image file_exists(exporting_path + "satellite.png")? (exporting_path + "satellite.png") : default_background_image  transparency: 0.2 refresh: true;
			species OSM_agent;
			
			}
			
		}
	}
