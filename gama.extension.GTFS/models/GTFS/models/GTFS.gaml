/**
* Name: GTFS
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model GTFS
global{
	
	string osmFolder <- "../../../includes/";
	string osmFile <- "../includes/map.osm";
	file<geometry> osmfileWitouthFiltering <- file<geometry>(osm_file(osmFile));
	geometry shape <- envelope(osmfileWitouthFiltering);
	//geometry shape <- (rectangle({0,0}, {28000.0,18000.0}));
	
	string gtfsFolder <- "tisseo_gtfs_v2/";
	
	//GTFS files
	string stops_file <- gtfsFolder + "stops.txt";
	string trips_file <- gtfsFolder + "trips.txt";
	string stop_times_file <- gtfsFolder + "stop_times.txt";
	string routes_file <- gtfsFolder + "routes.txt";
	string shapes_file <- gtfsFolder + "shapes.txt";
	
	
	//CSV files
	csv_file stops_csv <- csv_file(stops_file, ",", true);
	csv_file trips_csv <- csv_file(trips_file, ",", true);
	csv_file stop_times_csv <- csv_file(stop_times_file, ",", true);
	csv_file routes_csv <- csv_file(routes_file, ",", true);
	csv_file shapes_csv <- csv_file(shapes_file, ",", true);
	
	//Matrices
	matrix stops_mat <- stops_csv.contents;
	matrix shapes_mat <- shapes_csv.contents;
	matrix trips_mat <- trips_csv.contents;
	matrix routes_mat <- routes_csv.contents;
	matrix stop_times_mat <- stop_times_csv.contents;
	
	
	
	//GTFS Agents
	gtfsData gtfsDataAgent;
	
	// To change the location of stops
	list<point> shapePoints <- [];
	
	
	
	// Driving skills parameters
	float lane_width_ <- 0.7; 
	graph ROAD_NETWORK;
	
	// Simulation parameters
	float step <- 0.1 #s;
	date starting_date <- date(string("2020-03-10 08:00:00"));
	
	// To keep in memory lanched trips
	list<gtfsTrip> launchedTrips <- [];
	

	init {
		
		create gtfsData;
		gtfsDataAgent <- gtfsData[0];
		
		do gtfsDataExtraction;	
		do gtfsDataProcessing;
		do gtfsNetworkCreation;

		
	}
	
	
	
	action gtfsNetworkCreation{
		
		write("gtfsNetworkCreation...");
		
		// Create a graph representing the road network, with road lengths as weights
		map edge_weights <- routeShape as_map (each::(each.shape.perimeter / ( each.maxspeed  ) ) );
		ROAD_NETWORK <- as_driving_graph(routeShape, gtfsBusStop) with_weights edge_weights;
		
		
		ask gtfsBusStop{
			
			if(length(roads_in)>1 and length(roads_out)>1){
				baseColor_ <- #green;
			}else if(length(roads_in)>0 or length(roads_out)>0){
				baseColor_ <- #orange;
			}else{
				baseColor_ <- #red;
			}
			
		}
		
		ask routeShape{
			
			if(source_node != nil and target_node!=nil){
				baseColor_ <- #green;
			}else if(source_node != nil or target_node!=nil){
				baseColor_ <- #orange;
			}else{
				baseColor_ <- #red;
			}
			
		}
	}

	
	action gtfsDataExtractionStops{
		
		write("gtfsDataExtractionStops...");
		
		loop _row over: rows_list(stops_mat){
			
			string stopId <-_row[0];
			
			if stopId contains("stop_area"){
				
				create gtfsBusStopArea{
				id_ <-_row[0];
				name <- id_;
				stopCode_ <-_row[1];
				stopName_<-_row[2];
				lat_ <-float(_row[3]);
				lon_ <-float(_row[4]);
				locationType_<-_row[5];
				parentStation_<-_row[6];
				wheelchairBoarding_<-_row[7];
				
				location <-point(to_GAMA_CRS({lon_, lat_,0.0},"EPSG:4326"));
				
	
				
	
			}
					
			}else{
				
				create gtfsBusStop{
				id_ <-_row[0];
				name <- id_;
				stopCode_ <-_row[1];
				stopName_<-_row[2];
				lat_ <-float(_row[3]);
				lon_ <-float(_row[4]);
				locationType_<-_row[5];
				parentStation_<-_row[6];
				wheelchairBoarding_<-_row[7];
				
				location <-point(to_GAMA_CRS({lon_, lat_,0.0},"EPSG:4326"));
				
				
				gtfsDataAgent.busStopsMap[name]<-self;
				
				
	
			}
				
			}
			
			
		}	
		
		
	}
	
	action gtfsDataExtractionShapes{
		
		write("gtfsDataExtractionShapes...");
		
		string curr_id<-"";
		list<point> curr_shape <- [];
		map<string, list<point>> shape_map;
		list<gtfsBusStop> busStopsOnShape <- [];
		
		// Create shapes with busStops as nodes
		loop _row over: rows_list(shapes_mat){
			
			

			string shapeId <- string(int(_row[0]));
			string shapePtLat_ <- _row[1];
			string shapePtLon_ <- _row[2];
			string shapeDistTraveled_ <- _row[3];
			string shapePtSequence_ <- _row[4];
				
			
			
			if (shapeId != curr_id){
				
				if(length(curr_shape) >0){
					shape_map[string(int(curr_id))]<-curr_shape;
					
				}
				
				
				curr_id <- shapeId;
				curr_shape <- [];
				busStopsOnShape <- [];
				
				list<gtfsTrip> shapeTrips <- gtfsTrip where (each.shapeId_ = shapeId);
				loop _trip over: shapeTrips{
					loop _stop over: _trip.busStops_{
						
						if not ( busStopsOnShape contains _stop){
							add _stop to: busStopsOnShape;
						}
					}
					
				}
				
				

			}
			
			point shapePoint <- point(to_GAMA_CRS({float(shapePtLon_), float(shapePtLat_),0.0},"EPSG:4326"));
			
			//gtfsBusStop busStopLocatedAtPoint <- busStopsOnShape first_with (distance_to(each.location,shapePoint) < 1);
			
			gtfsBusStop busStopLocatedAtPoint <- busStopsOnShape first_with (each.location=shapePoint);
			
			list<point> stopsLocation <- busStopsOnShape collect (each.location);
			
			//write "busStopsOnShape "+ string(busStopsOnShape) color: #red ;		
			//write("shapePoint "+ shapePoint);
			//write("stopsLocation "+ stopsLocation);
			
			
			
		 	if (busStopLocatedAtPoint != nil) and length(curr_shape) >0{
		 		
		 		shapePoint <- busStopLocatedAtPoint.location;
		 		
		 		//write("busStopLocatedAtPoint "+ busStopLocatedAtPoint) color: #green;
		 		add shapePoint to: curr_shape;
				shape_map[string(int(curr_id)) + "_" + busStopLocatedAtPoint.id_]<-curr_shape;
				curr_shape <- [];
				
				
			}
			

			
		 	add shapePoint to: curr_shape;
		}
		
		
		loop _shapeID over: shape_map.keys{
			
			if length(shape_map[_shapeID]) > 1{
				
				create routeShape{
					
					name <- _shapeID;
					id_ <- _shapeID;
					pointList_ <- shape_map[_shapeID];
					shape <- polyline(shape_map[_shapeID]);
					
					create routeShape{
						
						name <- myself.name;
						id_ <- myself.id_;
						pointList_ <- myself.pointList_;
						shape <- polyline(reverse(shape_map[_shapeID]));
						linked_road <- myself;
						myself.linked_road <- self;
						
					}
				}
			}
			
				
		}
		
	}
	
	action gtfsDataExtractionPoints{
		
		write("gtfsDataExtractionPoints...");
		
		
		
		
		// Get all points
		loop _row over: rows_list(shapes_mat){
			
			string shapePtLat_ <- _row[1];
			string shapePtLon_ <- _row[2];

			
			point shapePoint <- point(to_GAMA_CRS({float(shapePtLon_), float(shapePtLat_),0.0},"EPSG:4326"));
		
		 	add shapePoint to: shapePoints;
		}
		
		// Set location of busStops on shapes
		ask gtfsBusStop{
			
			location <- closest_to (shapePoints, self.location); 
			
		}
		
		
		
		
		
	}
	
	action gtfsDataExtractionTrips{
		
		write("gtfsDataExtractionTrips...");
		
		loop _row over: rows_list(trips_mat){
			
			create gtfsTrip{
				
				routeId_<- _row[0];
				serviceId_<- _row[1];
				id_<- _row[2];
				name <- id_;
				directionId_<- _row[3];
				tripHeadsign_<- _row[4];
				shapeId_<- _row[5];
				

					
				gtfsDataAgent.tripsMap[name]<-self;
				
				add self to: gtfsDataAgent.routesMap[routeId_].trips_;
				
				
					
						
			}
		}
		
		
	}
	
	action gtfsDataExtractionRoutes{
		
		write("gtfsDataExtractionRoutes...");
		
		loop _row over: rows_list(routes_mat){
			
			create gtfsRoute{
				
				id_<- _row[0];
				name <- _row[2];
				agencyId_<- _row[1];
				routeShortName_<- _row[2];
				routeLongName_<- _row[3];
				routeColor_<- _row[4];
				routeTextColor_<- _row[5];
				routeType_<- _row[6];
				
				gtfsDataAgent.routesMap[id_]<-self;

						
			}
		}
		
		
	}
	
	action gtfsDataExtractionStopTimes{
		
		write("gtfsDataExtractionStopTimes...");
		
		loop _row over: rows_list(stop_times_mat){
			

				
			string tripId_<- string(int(_row[0])) ;
			string arrivalTime_<- _row[1];
			string departureTime_<- _row[2];
			string stopId_<- _row[3];
			string pickupType_<- _row[4];
			string dropOffType_<- _row[5];
			string stopSequence_<- _row[6];
			string shapeDistTraveled_<- _row[7];
			string timePoint_<- _row[8];
			string stopHeadSign_<- _row[9];
			
			gtfsBusStop currentGtfsBusStop <- gtfsDataAgent.busStopsMap[stopId_];
			gtfsTrip currentTrip <- gtfsDataAgent.tripsMap[tripId_];
			
			if currentGtfsBusStop != nil and currentTrip != nil{
				add currentGtfsBusStop to: currentTrip.busStops_;
								
				add currentGtfsBusStop.id_ to: currentTrip.busStopsIds_;
				add currentGtfsBusStop.stopName_ to: currentTrip.busStopsNames_;
				add arrivalTime_ to: currentTrip.busStopsTimes_;
				
			}
			
			if(currentTrip != nil and stopSequence_ = "1"){
				currentTrip.departureString_ <- arrivalTime_;
				currentTrip.departureInSeconds_ <- timeStringToSeconds(arrivalTime_);
				
			}
			
			

						
			
		}
		
		
	}
	
	action gtfsDataExtraction{
			
		do gtfsDataExtractionStops;
		do gtfsDataExtractionPoints;
		do gtfsDataExtractionRoutes;
		do gtfsDataExtractionTrips;
		do gtfsDataExtractionStopTimes;
		do gtfsDataExtractionShapes;
		
		
		
	} 
	
	action gtfsDataProcessing{
		write("gtfsDataProcessing...");
		
		ask gtfsRoute{
			//Filter by direction
			loop _trip over: trips_{
				
				_trip.line_ <- routeShortName_;
				
				add _trip to: tripsByDirection_[_trip.directionId_];
				
				
				loop _busStop over: _trip.busStops_{
					
					if !(_busStop.busLines_ contains routeShortName_){
						add routeShortName_ to: _busStop.busLines_;
					}
					if !(_busStop.headings_ contains _trip.tripHeadsign_){
						add _trip.tripHeadsign_ to: _busStop.headings_;
					}
					
					
					
				}
				
			}
			
			//Sort by departure
			sortedTripsByDirection_0_ <- (tripsByDirection_["0"] sort_by (each.departureInSeconds_)) collect each.id_;
			sortedTripsByDirection_1_ <- (tripsByDirection_["1"] sort_by (each.departureInSeconds_)) collect each.id_;


		}
		
		
		
		
	}
	
	
	int timeStringToSeconds(string _timeString){
		
		int result <- 0;
		
		list<string> timeStringList <- _timeString split_with (':', true);
		result <- result + int(timeStringList[0]) * 3600;
		result <- result + int(timeStringList[1]) * 60;
		result <- result + int(timeStringList[2]) ;
		
		return result;
		
	}
	
	
	reflex generateBuses{
		

	
		ask gtfsTrip{
			
			
			string hourDeparture <- self.departureString_;
			string currentHour <- myself.hourToString(current_date);
			
			
			if(hourDeparture = currentHour and not (launchedTrips contains self)){
			
				add self to: launchedTrips;
				
				write"Bus creation" color: #red;
				write("departureString_ " + departureString_);
				write("routeId_ " + routeId_);
				write("directionId_ " + directionId_);
				write("tripHeadsign_ " + tripHeadsign_);
				write("line_ " + line_);

				write(string(first(busStops_)) + " " + string(last(busStops_)));
				write(string(first(busStopsNames_)) + " -> " + string(last(busStopsNames_)));
				write(" ");
				
				create bus{
					
					graph_ <- ROAD_NETWORK;
					originAndTargets_ <- myself.busStops_;
					location <- first(myself.busStops_).location;
					baseColor_ <- rgb("#"+gtfsDataAgent.routesMap[myself.routeId_].routeColor_);
					
				}
			}
			
		}
	
	
	}
	
	string hourToString(date _value){
		string stringValue <- string(_value);
		
		stringValue <- split_with(stringValue," ",false)[1];
		
		
		
		return stringValue;
	}
	
}
	





species baseAgent{
	
	string id_ <- "";
	rgb baseColor_ <- #white;
	
	
	
	int timeStringToSeconds(string _timeString){
		
		int result <- 0;
		
		list<string> timeStringList <- _timeString split_with (':', true);
		result <- result + int(timeStringList[0]) * 3600;
		result <- result + int(timeStringList[1]) * 60;
		result <- result + int(timeStringList[2]) ;
		
		return result;
		
	}
	
}

species baseGeographicAgent parent: baseAgent{
	
	float lat_;
	float lon_;
	
}


species routeShape parent: baseAgent skills: [road_skill] {
	
	
	list<point> pointList_;
	
	
	init{
		
		num_lanes <- 5;
		maxspeed <- 100 #km / #h;
		
	}
	
	aspect base {
		draw shape color: baseColor_ end_arrow: 0.5; 
		
			
		/*loop _pt over: pointList_{
			draw circle(0.5) color: #white at: _pt; 
		}*/

	}
}

species gtfsTrip parent: baseAgent{
	
	string routeId_;
	string serviceId_;
	string directionId_;
	string tripHeadsign_;
	string shapeId_;
	
	string line_;
	
	string departureString_;
	int departureInSeconds_;
	
	list<gtfsBusStop> busStops_ <- [];
	list<string> busStopsIds_ <- [];
	list<string> busStopsNames_ <- [];
	list<string> busStopsTimes_ <- [];
}

species gtfsRoute parent: baseAgent{
	

	string agencyId_;
	string routeShortName_;
	string routeLongName_;
	string routeColor_;
	string routeTextColor_;
	string routeType_;
	
	
	list<gtfsTrip> trips_ <- [];
	map<string, list<gtfsTrip>> tripsByDirection_;
	
	list<string> sortedTripsByDirection_0_ <- [];
	list<string> sortedTripsByDirection_1_ <- [];
	
	init{
		tripsByDirection_["0"]<-[];
		tripsByDirection_["1"]<-[];
	}
}




species gtfsBusStop parent: baseGeographicAgent skills: [intersection_skill]{

	string stopCode_;
	string stopName_;
	string locationType_;
	string parentStation_;
	string wheelchairBoarding_;
	
	list<string> busLines_ <-[];
	list<string> headings_ <-[];
	
	
	
	aspect base { 
		draw circle(10) color: baseColor_ ;
	}
	
	
} 

species gtfsBusStopArea parent: gtfsBusStop{


	
	
	aspect base { 
		draw circle(1) color: #red ;
	}
	
	
} 





species gtfsData{
	
	map<string,gtfsBusStop> busStopsMap;
	map<string,gtfsTrip> tripsMap;
	map<string,gtfsRoute> routesMap;
}


species bus  skills: [driving]{
	
	
	graph graph_;
	
	rgb baseColor_ <- #yellow;
	list<gtfsBusStop> originAndTargets_ <- [];
	int targetIndice_ <- 1;
	
	// Driving
	point posOnRoad_ <- {0, 0};
	float vehiculeWidth_ <- lane_width_ * num_lanes_occupied;
	
	string STATE_ <- "INITIALIZING";

	
	init{
		num_lanes_occupied <- 2;
		vehicle_length <- 10 #m;
		max_speed <- 100 #km / #h;
		max_acceleration <- 3.5;
	}
	

	

	
	point compute_position {
		// Shifts the position of the vehicle perpendicularly to the road,
		// in order to visualize different lanes
		if (current_road != nil) {
			
			float dist <- (routeShape(current_road).num_lanes - lowest_lane -
				mean(range(num_lanes_occupied - 1)) - 0.5) * lane_width_;

		 	point shift_pt <- {cos(heading + 90) * dist, sin(heading + 90) * dist};	
		
			return location + shift_pt;

			
		} else {
			return {0, 0};
		}
	}
	
	

	
	
	aspect base {

		posOnRoad_ <- compute_position();
		
		draw rectangle(vehicle_length, lane_width_ * num_lanes_occupied) 
			at: posOnRoad_ color: baseColor_ rotate: heading border: #black;
		draw triangle( lane_width_ * num_lanes_occupied) 
			at: posOnRoad_ color: #white rotate: heading + 90 border: #black;

		

	}
	
	
	

	

	
	


	reflex baseMovingAgentStateMachineCycle{
		
		// Transitions
		switch STATE_ {
			match "INITIALIZING" {
				
				if isPathCreationReady(){
					do setPathToNextTarget;
					STATE_ <- "WAITING_PATH";
				}
			} 
			match "WAITING_PATH" {
				if isPathReady(){
					STATE_ <- "DRIVING";
				}
			} 
			match "DRIVING" {
			
				if isFinalTargetReached(){
					STATE_ <- "DYING";
					do dieCustom;
				}else if isIntermediateTargetReached(){
					STATE_ <- "WAITING_PATH";
					do setNextTarget;
					do setPathToNextTarget;
				}
			}
			match "DYING" {

			}

		}
		
		// Action
		switch STATE_ {
			match "INITIALIZING" {
				
			} 
			match "WAITING_PATH" {
				
			} 
			match "DRIVING" {
				do driveOnPath;
			}
			match "DYING" {
				
			}

		}
		
	}
	
	
	
	bool isPathCreationReady{
		return (current_path = nil) and (length(originAndTargets_) > 1);
	}
	
	bool isPathReady{
		return current_path != nil;
	}
	
	bool isFinalTargetReached{
		
		return location = last(originAndTargets_).location;
	}
	
	
	bool isIntermediateTargetReached{
		return location = originAndTargets_[targetIndice_].location;
	}
	
	

	action driveOnPath{
		do drive;
	}
	
	action setPathToNextTarget{
		list<gtfsBusStop> dst_nodes <- [originAndTargets_[targetIndice_-1], originAndTargets_[targetIndice_]];
		do compute_path graph: graph_ nodes: dst_nodes;
	}
	
	action setNextTarget{
		targetIndice_ <- targetIndice_ + 1;
	}
	
	action dieCustom{


		do unregister;
		do die; 
	}
}




experiment loadGTFSData type: gui {
	
	
	output {
		display map type: 3d background: #gray{
			graphics "world" {
				draw rectangle({-16000.0,-23000.0}, {28000.0,18000.0}).contour;
			}
			
			

			
			species gtfsBusStop aspect: base  refresh: false  ;
			species routeShape aspect: base  refresh: false  ;
			species bus aspect: base ;
			
			
			
		}
	}
}
