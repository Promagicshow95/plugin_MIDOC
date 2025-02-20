/**
* Name: GTFSTest
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model GTFSTest

global{
	
	float step <- 0.1 #s;
	date starting_date <- date(string("2020-03-10 08:00:00"));
	
	// To keep in memory lanched trips
	list<gtfsTrip> launchedTrips <- [];
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

