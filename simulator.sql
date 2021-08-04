BEGIN
	
	SET @`year` = 1;
	
	WHILE @`year` <= 100
	
	DO
	
		IF @`year` != 1
		THEN 	
			INSERT INTO simulator.system (`year`, system_id, system_rating)
				SELECT @`year` AS `year`
					  , system_id
					  , ROUND(s.system_rating + simulator.gauss(0, 1), 2) AS system_rating
				FROM simulator.system AS s
				WHERE s.`year` = @`year` - 1;
		END IF;
	
		SET @system_id = 1;
		
		WHILE @system_id <= 8
		
		DO
		
			SET @system_rating = (SELECT s.system_rating FROM simulator.system AS s WHERE s.`year` = @`year` AND s.system_id = @system_id);
			
			DROP TABLE IF EXISTS simulator.temp;
				
			CREATE TABLE simulator.temp (id INT AUTO_INCREMENT, division INT, `rank` INT, team_id INT, team_name VARCHAR(50), rating FLOAT, PRIMARY KEY (id));	
			
			IF @`year` = 1
			THEN
				INSERT INTO simulator.temp (division, `rank`, team_id, team_name, rating)
					SELECT CASE WHEN sq.id BETWEEN 1 AND 20 THEN 1
									WHEN sq.id BETWEEN 21 AND 40 THEN 2
									WHEN sq.id BETWEEN 41 AND 60 THEN 3
									WHEN sq.id BETWEEN 61 AND 80 THEN 4
									END AS division
						 , IF(sq.id >= 61, sq.id - 60, IF(sq.id >= 41, sq.id - 40, IF(sq.id >= 21, sq.id - 20, sq.id))) AS `rank`
						 , sq.team_id
						 , sq.team_name
						 , sq.rating
					FROM (
						SELECT @rownumber := @rownumber + 1 AS id
							  , sq.team_id
							  , sq.team_name
							  , ROUND(@system_rating + 5 - 10 / 20 * (@rownumber - 1), 2) AS rating
						FROM (
							SELECT t.team_id
								  , t.team_name
							FROM simulator.team AS t
							WHERE t.system_id = @system_id
							ORDER BY RAND()
							) AS sq
						CROSS JOIN (SELECT @rownumber := 0) AS dummy
						) AS sq;
			ELSE
				INSERT INTO simulator.temp (division, `rank`, team_id, team_name, rating)
					SELECT r.division
						  , t.`rank`
						  , r.team_id
						  , r.team_name
						  , r.rating
					FROM simulator.rating AS r
						JOIN simulator.`table` AS t ON r.team_id = t.team_id
					WHERE r.`year` = @`year` - 1
						AND r.system_id = @system_id
						AND t.`year` = @`year` - 1
						AND t.gameweek = 38
					ORDER BY r.division ASC
							 , t.`rank` ASC;
							 
				### Promotion
				
				UPDATE simulator.temp
				SET division = division - 1, rating = rating + 2.5
				WHERE division != 1 AND `rank` IN (1, 2, 3, 4);
									
				### Relegation
				
				UPDATE simulator.temp
				SET division = division + 1, rating = rating - 2.5
				WHERE division != 4 AND `rank` IN (17, 18, 19, 20);
			END IF;
				
			### Cycling through divisions
			
			SET @division = 1;
			
			WHILE @division <= 4
			
			DO
			
				SET @league_rating = @system_rating - ((@division - 1) * 10);
			
				DROP TABLE IF EXISTS simulator.temp_2;
				
				CREATE TABLE simulator.temp_2 (id INT, team_id INT, team_name VARCHAR(50), rating FLOAT, PRIMARY KEY (id));
				
				INSERT INTO simulator.temp_2 (id, team_id, team_name, rating)
					SELECT t.id
						  , t.team_id
						  , t.team_name
						  , t.rating
					FROM simulator.temp AS t
					WHERE t.division = @division;
						
				### Randomly modifying the ratings but making sure that certain conditions are met via a procedure
						
				SET @variable = 0;
				
				SET @counter = 0;
			
				WHILE @variable = 0
				
				DO
				
					DROP TABLE IF EXISTS simulator.temp_3;
					
					CREATE TABLE simulator.temp_3 (id INT, team_id INT, team_name VARCHAR(50), rating FLOAT, PRIMARY KEY (id));
					
					INSERT INTO simulator.temp_3
						SELECT t2.id
							  , t2.team_id
							  , t2.team_name
							  , ROUND(t2.rating + simulator.gauss(0, 2), 2) AS rating
						FROM simulator.temp_2 AS t2;
					
					SET @normaliser = (SELECT AVG(rating) FROM simulator.temp_3) - @league_rating;
				
					DROP TABLE IF EXISTS simulator.temp_4;
					
					CREATE TABLE simulator.temp_4 (id INT, team_id INT, team_name VARCHAR(50), rating FLOAT, PRIMARY KEY (id));
					
					INSERT INTO simulator.temp_4
						SELECT t3.id
							  , t3.team_id
							  , t3.team_name
							  , ROUND(t3.rating - @normaliser, 2) AS rating
						FROM simulator.temp_3 AS t3;
					
					SET @maximum = (SELECT MAX(t4.rating) FROM simulator.temp_4 AS t4);
					
					SET @minimum = (SELECT MIN(t4.rating) FROM simulator.temp_4 AS t4);
					
					SET @deviation = (SELECT STDDEV(t4.rating) FROM simulator.temp_4 AS t4);
					
					SET @bottom_deviation = (
						SELECT STDDEV(sq1.rating)
						FROM (
							SELECT *
							FROM simulator.temp_4 AS t4
							ORDER BY t4.rating ASC
							LIMIT 10
							) AS sq1
						);
					
					IF @maximum BETWEEN @league_rating + 5 AND @league_rating + 10
						AND @minimum BETWEEN @league_rating - 10 AND @league_rating - 5
						AND @deviation > 3
						AND @bottom_deviation < 1.5
					THEN
						SET @variable = 1;
					END IF;
					
					SET @counter = @counter + 1;
					
					END WHILE;
				
				### Adding attack and defence ratings
				
				DROP TABLE IF EXISTS simulator.temp_5;
				
				CREATE TABLE simulator.temp_5 (id INT, team_id INT, team_name VARCHAR(50), rating FLOAT, att_rating FLOAT, def_rating FLOAT, PRIMARY KEY (id));
				
				IF @`year` = 1
				THEN
					INSERT INTO simulator.temp_5 (id, team_id, team_name, rating, att_rating, def_rating)
						SELECT t4.id
							  , t4.team_id
							  , t4.team_name
							  , t4.rating
							  , ROUND(t4.rating + simulator.gauss(0, 1), 2) AS att_rating
							  , NULL AS def_rating
						FROM simulator.temp_4 AS t4;
				ELSE
					INSERT INTO simulator.temp_5 (id, team_id, team_name, rating, att_rating, def_rating)
						SELECT t4.id
							  , t4.team_id
							  , t4.team_name
							  , t4.rating
							  , ROUND(t4.rating + sq.ad_differential + simulator.gauss((sq.ad_differential / - 5), 1), 2) AS att_rating
							  , NULL AS def_rating
						FROM simulator.temp_4 AS t4
						JOIN (
							SELECT r.team_id
								  , ROUND(r.att_rating - r.rating, 2) AS ad_differential
							FROM simulator.rating AS r
							WHERE r.`year` = @`year` - 1
							) AS sq
							ON t4.team_id = sq.team_id;
				END IF;
				
				UPDATE simulator.temp_5
				SET att_rating = rating + 2.5
				WHERE att_rating > rating + 2.5;
				
				UPDATE simulator.temp_5
				SET att_rating = rating - 2.5
				WHERE att_rating < rating - 2.5;
				
				UPDATE simulator.temp_5
				SET def_rating = rating + (rating - att_rating);
				
				### Adding fixture slots
				
				DROP TABLE IF EXISTS simulator.temp_6;
				
				CREATE TABLE simulator.temp_6 (id INT, team_id INT, team_name VARCHAR(50), rating FLOAT, att_rating FLOAT, def_rating FLOAT, fixture_slot INT, PRIMARY KEY (id), INDEX team_id (team_id)) AS
				
					SELECT t5.id
						  , t5.team_id
						  , t5.team_name
						  , t5.rating
						  , t5.att_rating
						  , t5.def_rating
						  , sq.fixture_slot
					FROM simulator.temp_5 AS t5
						JOIN (
							SELECT sq.id
								  , @rownumber := @rownumber + 1 AS fixture_slot
							FROM (
								SELECT t5.id
								FROM simulator.temp_5 AS t5
								ORDER BY RAND()
								) AS sq
							JOIN (SELECT @rownumber := 0) AS dummy
							) AS sq
							ON t5.id = sq.id
					ORDER BY t5.id;
	
				### Storing the start of season ratings in a table
				
				INSERT INTO simulator.rating (`year`, system_id, division, team_id, team_name, rating, att_rating, def_rating)
					SELECT @`year`
						  , @system_id
						  , @division
						  , t6.team_id
						  , t6.team_name
						  , t6.rating
						  , t6.att_rating
						  , t6.def_rating
					FROM simulator.temp_6 AS t6;
					
				### This is where the actual results are generated
					
				SET @gameweek = 1;
			
				WHILE @gameweek <= 38
				
				DO
				
					### Temporary table necessary for stabilising random numbers
					
					DROP TEMPORARY TABLE IF EXISTS simulator.stabiliser;
					
					CREATE TEMPORARY TABLE simulator.stabiliser
						(
						  gameweek INT
						, fixture INT
						, team_id_h INT
						, team_name_h VARCHAR(100)
						, rating_h FLOAT
						, att_rating_h FLOAT
						, def_rating_h FLOAT
						, team_id_a INT
						, team_name_a VARCHAR(100)
						, rating_a FLOAT
						, att_rating_a FLOAT
						, def_rating_a FLOAT
						, potential_h INT
						, rand_h FLOAT
						, potential_a INT
						, rand_a FLOAT
						, PRIMARY KEY (gameweek, fixture)
						);
						
					INSERT INTO simulator.stabiliser (gameweek
															  , fixture
															  , team_id_h
															  , team_name_h
															  , rating_h
															  , att_rating_h
															  , def_rating_h
															  , team_id_a
															  , team_name_a
															  , rating_a
															  , att_rating_a
															  , def_rating_a
															  , potential_h
															  , rand_h
															  , potential_a
															  , rand_a)			  
						SELECT sq.`*`
							  , ROUND(sq.att_rating_h - sq.def_rating_a + 50) AS potential_h
							  , ROUND(RAND(), 5) AS rand_h
							  , ROUND(sq.att_rating_a - sq.def_rating_h + 50) AS potential_a
							  , ROUND(RAND(), 5) AS rand_a
						FROM (
							SELECT s.gameweek
								  , s.fixture
								  , t6h.team_id AS team_id_h
								  , t6h.team_name AS team_name_h
								  , ROUND(t6h.rating * (@home_advantage + IFNULL(fh.form / 100, 0)), 2) AS rating_h
								  , ROUND(t6h.att_rating * (@home_advantage + IFNULL(fh.form / 100, 0)), 2) AS att_rating_h
								  , ROUND(t6h.def_rating * (@home_advantage + IFNULL(fh.form / 100, 0)), 2) AS def_rating_h
								  , t6a.team_id AS team_id_a
								  , t6a.team_name AS team_name_a
								  , ROUND(t6a.rating * (2 - (@home_advantage - IFNULL(fa.form / 100, 0))), 2) AS rating_a
								  , ROUND(t6a.att_rating * (2 - (@home_advantage - IFNULL(fa.form / 100, 0))), 2) AS att_rating_a
								  , ROUND(t6a.def_rating * (2 - (@home_advantage - IFNULL(fa.form / 100, 0))), 2) AS def_rating_a
							FROM simulator.temp_6 AS t6h
								JOIN simulator.`schedule` AS s
									ON t6h.fixture_slot = s.home
								JOIN simulator.temp_6 AS t6a
									ON s.away = t6a.fixture_slot
								LEFT JOIN simulator.form AS fh
									ON t6h.team_id = fh.team_id
										AND fh.gameweek = @gameweek - 1
										AND fh.`year` = @`year`
										AND fh.system_id = @system_id
										AND fh.division = @division
								LEFT JOIN simulator.form AS fa
										ON t6a.team_id = fa.team_id
										AND fa.gameweek = @gameweek - 1
										AND fa.`year` = @`year`
										AND fa.system_id = @system_id
										AND fa.division = @division
							WHERE s.gameweek = @gameweek
								) AS sq;
				
					INSERT INTO simulator.result (`year`
						 								 , system_id
														 , division
														 , gameweek
														 , fixture
														 , team_id_h
														 , team_name_h
														 , rating_h
														 , att_rating_h
														 , def_rating_h
														 , team_id_a
														 , team_name_a
														 , rating_a
														 , att_rating_a
														 , def_rating_a
														 , potential_h
														 , rand_h
														 , potential_a
														 , rand_a
														 , goals_h
														 , goals_a)
						SELECT @`year` AS `year`
							  , @system_id AS system_id
							  , @division AS division
							  , st.`*`
							  , IF(sc1.goals IS NULL, 0, MAX(sc1.goals)) AS goals_h
							  , IF(sc2.goals IS NULL, 0, MAX(sc2.goals)) AS goals_a
						FROM simulator.stabiliser AS st
						LEFT JOIN simulator.score AS sc1
							ON st.potential_h = sc1.potential
							AND st.rand_h > sc1.rand_threshold
						LEFT JOIN simulator.score AS sc2
							ON st.potential_a = sc2.potential
							AND st.rand_a > sc2.rand_threshold
						GROUP BY st.gameweek
								 , st.fixture;
								 		
					INSERT INTO simulator.form (`year`
												  	  , system_id
													  , division
													  , gameweek
													  , team_id
													  , team_name
													  , formR
													  , formRD
													  , formGD
													  , formNG
													  , formG
													  , form)
						SELECT @`year` AS `year`
							  , @system_id AS system_id
							  , @division AS division
							  , sq.`*`
							  , sq.formR + sq.formRD + sq.formGD AS formNG # Overall gameweek form value without gravity applied
							  , ROUND(sq.formR + sq.formRD + sq.formGD - (IFNULL(f.form, 0) / 5), 2) AS formG # And with gravity applied
							  , ROUND(sq.formR + sq.formRD + sq.formGD - (IFNULL(f.form, 0) / 5) + IFNULL(f.form, 0), 2) AS form # Cumulative
						FROM (
							SELECT r.gameweek
								  , r.team_id_h AS team_id
								  , r.team_name_h AS team_name
								  , IF(r.goals_h > r.goals_a, 0.5, IF(r.goals_h = r.goals_a, 0, -0.5)) AS formR
								  , ROUND((r.rating_a - r.rating_h) / 20, 2) AS formRD
								  , ROUND(IF(ABS(r.goals_h - r.goals_a) = 1, 0, (r.goals_h - r.goals_a) / 20), 2) AS formGD
							FROM simulator.result AS r
							WHERE r.`year` = @`year`
								AND r.system_id = @system_id
								AND r.division = @division
								AND r.gameweek = @gameweek
							
							UNION
							
							SELECT r.gameweek
								  , r.team_id_a
								  , r.team_name_a
								  , IF(r.goals_a > r.goals_h, 0.5, IF(r.goals_a = r.goals_h, 0, -0.5)) AS formR
								  , ROUND((r.rating_h - r.rating_a) / 20, 2) AS formRD
								  , ROUND(IF(ABS(r.goals_a - r.goals_h) = 1, 0, (r.goals_a - r.goals_h) / 20), 2) AS formGD
							FROM simulator.result AS r
							WHERE r.`year` = @`year`
								AND r.system_id = @system_id
								AND r.division = @division
								AND r.gameweek = @gameweek
							) AS sq
							LEFT JOIN simulator.form AS f
								ON sq.team_id = f.team_id
									AND f.`year` = @`year`
									AND sq.gameweek = f.gameweek + 1;
						
					### Creating human-readable league tables on a per-gameweek basis and sticking them in a "tables" table
				
					INSERT INTO simulator.`table` (`year`
														  , system_id
														  , division
														  , gameweek
														  , `rank`
														  , team_id
														  , team_name
														  , W
														  , D
														  , L
														  , GF
														  , GA
														  , GD
														  , Pts)	
						SELECT @`year` AS `year`
							  , @system_id AS system_id
							  , @division AS division
							  , @gameweek AS gameweek
							  , ROW_NUMBER() OVER (ORDER BY sq.Pts DESC) AS `rank`
							  , sq.`*`
						FROM (
							SELECT cg.team_id
								  , cg.team_name
								  , cg.W + IFNULL(t.W, 0) AS W
								  , cg.D + IFNULL(t.D, 0) AS D
								  , cg.L + IFNULL(t.L, 0) AS L
								  , cg.GF + IFNULL(t.GF, 0) AS GF
								  , cg.GA + IFNULL(t.GA, 0) AS GA
								  , cg.GD + IFNULL(t.GD, 0) AS GD
								  , cg.Pts + IFNULL(t.Pts, 0) AS Pts
							FROM (
								SELECT sq.team_id
									  , sq.team_name
									  , sq.wins AS W
									  , IF(sq.wins = 0 AND sq.losses = 0, 1, 0) AS D
									  , sq.losses AS L
									  , sq.goals_for AS GF
									  , sq.goals_against AS GA
									  , sq.goals_for - sq.goals_against AS GD
								 	  , IF(sq.wins = 1, 3, IF(sq.losses = 1, 0, 1)) AS Pts 
								FROM (
									SELECT r.team_id_h AS team_id
										  , r.team_name_h AS team_name
										  , SUM(IF(r.goals_h > r.goals_a, 1, 0)) AS wins
									     , SUM(IF(r.goals_h < r.goals_a, 1, 0)) AS losses
									     , SUM(r.goals_h) AS goals_for
									     , SUM(r.goals_a) AS goals_against
									FROM simulator.result AS r
									WHERE r.`year` = @`year`
										AND r.system_id = @system_id
										AND r.division = @division
										AND r.gameweek = @gameweek
									GROUP BY r.team_id_h
										
									UNION
									
									SELECT r.team_id_a
										  , r.team_name_a
										  , SUM(IF(r.goals_a > r.goals_h, 1, 0)) AS wins
										  , SUM(IF(r.goals_a < r.goals_h, 1, 0)) AS losses
										  , SUM(r.goals_a) AS goals_for
										  , SUM(r.goals_h) AS goals_against
									FROM simulator.result AS r
									WHERE r.`year` = @`year`
										AND r.system_id = @system_id
										AND r.division = @division
										AND r.gameweek = @gameweek
									GROUP BY r.team_id_a
									) AS sq
								) AS cg # Current gameweek mini-table
							LEFT JOIN simulator.`table` AS t
								ON cg.team_id = t.team_id
									AND t.`year` = @`year`
									AND t.gameweek = @gameweek - 1
							) AS sq;
						
					SET @gameweek = @gameweek + 1;
					
					END WHILE;
				
				SET @division = @division + 1;
				
				END WHILE;
		
			SET @system_id = @system_id + 1;
			
			END WHILE;
		
		### Table shifting

		INSERT INTO simulator.result_repository (id, `year`, system_id, division, gameweek, fixture, team_id_h, team_name_h, rating_h, att_rating_h,
															  def_rating_h, team_id_a, team_name_a, rating_a, att_rating_a, def_rating_a, potential_h, rand_h, potential_a, rand_a,
															  goals_h, goals_a)
			SELECT id + 1823995, `year`, system_id, division, gameweek, fixture, team_id_h, team_name_h, rating_h, att_rating_h,
				    def_rating_h, team_id_a, team_name_a, rating_a, att_rating_a, def_rating_a, potential_h, rand_h, potential_a, rand_a,
				    goals_h, goals_a
			FROM simulator.result AS r
			WHERE r.`year` = @`year` - 1;
			
		DELETE FROM simulator.result
		WHERE `year` = @`year` - 1;

		INSERT INTO simulator.form_repository (id, `year`, system_id, division, gameweek, team_id, team_name, formR, formRD, formNG, formG, `form`)
			SELECT id + 3769589, `year`, system_id, division, gameweek, team_id, team_name, formR, formRD, formNG, formG, `form`
			FROM simulator.form AS f
			WHERE f.`year` = @`year` - 1;
			
		DELETE FROM simulator.form
		WHERE `year` = @`year` - 1;
		
		INSERT INTO simulator.table_repository (id, `year`, system_id, division, gameweek, `rank`, team_id, team_name, W, D, L, GF, GA, GD, Pts)
			SELECT id + 3769589, `year`, system_id, division, gameweek, `rank`, team_id, team_name, W, D, L, GF, GA, GD, Pts
			FROM simulator.`table` AS t
			WHERE t.`year` = @`year` - 1;
			
		DELETE FROM simulator.`table`
		WHERE `year` = @`year` - 1;
		
		SET @`year` = @`year` + 1;
		
		END WHILE;
	
	### Transfer residual data from live tables to repositories after final iteration
	
	INSERT INTO simulator.result_repository (id, `year`, system_id, division, gameweek, fixture, team_id_h, team_name_h, rating_h, att_rating_h,
														  def_rating_h, team_id_a, team_name_a, rating_a, att_rating_a, def_rating_a, potential_h, rand_h, potential_a, rand_a,
														  goals_h, goals_a)
		SELECT id + 1823995 AS id, `year`, system_id, division, gameweek, fixture, team_id_h, team_name_h, rating_h, att_rating_h,
			    def_rating_h, team_id_a, team_name_a, rating_a, att_rating_a, def_rating_a, potential_h, rand_h, potential_a, rand_a,
			    goals_h, goals_a
		FROM simulator.result AS r;
		
	TRUNCATE TABLE simulator.result;
	
	INSERT INTO simulator.form_repository (id, `year`, system_id, division, gameweek, team_id, team_name, formR, formRD, formNG, formG, `form`)
		SELECT id + 3769589 AS id, `year`, system_id, division, gameweek, team_id, team_name, formR, formRD, formNG, formG, `form`
		FROM simulator.form AS f;
		
	TRUNCATE TABLE simulator.form;
	
	INSERT INTO simulator.table_repository (id, `year`, system_id, division, gameweek, `rank`, team_id, team_name, W, D, L, GF, GA, GD, Pts)
		SELECT id + 3769589 AS id, `year`, system_id, division, gameweek, `rank`, team_id, team_name, W, D, L, GF, GA, GD, Pts
		FROM simulator.`table` AS t;
		
	TRUNCATE TABLE simulator.`table`;
	
END