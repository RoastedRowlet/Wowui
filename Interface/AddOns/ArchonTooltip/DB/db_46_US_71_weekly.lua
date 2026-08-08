local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Unknown-Unknown','Rogue-Assassination','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Warrior-Arms','Hunter-BeastMastery','Druid-Balance','Druid-Restoration','Mage-Fire','Warrior-Fury','DeathKnight-Unholy','Paladin-Protection','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Priest-Discipline','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Warlock-Demonology','Druid-Guardian','Paladin-Holy','Warlock-Destruction','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Evoker-Preservation','Warlock-Affliction','Mage-Arcane','Monk-Windwalker',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aarztok:BAAALgAECgUJBQABLgAFFAcJFgABAOwZAA==.',
Ac='Achepir:BAAALgADCgIJAgAAAA==.Achiella:BAAALgAECgEJAQAAAA==.',
Ad='Adino:BAAALgADCgEJAQAAAA==.Advisor:BAACLgAFFH8KAAICAAQJkRBeQADjAAACAAQJkRBeQADjAAAuAAQKfzQAAwIACQmcJG0JAOECAAIACQmcJG0JAOECAAMAAQl5F2+ZAEQAAAAA.',
Ae='Aería:BAAALgAECgYJDwAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgAECgMJBgAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgAECgEJAQAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aldiiran:BAAALgAECgEJAQABLgAFFAQJCQAEAGwcAA==.Aldoraine:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Altrix:BAAALgAECgUJBgABLgAFFAMJBQAGABkDAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgAECgMJAwAAAA==.Alyà:BAAALgAECgIJAwABLgAFFAYJFQAHAFELAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgAECgYJEgAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Anare:BAAALgAECgYJBgAAAA==.Anastaria:BAAALgAECggJCAAAAA==.Andolas:BAAALgAECgQJBAAAAA==.Angelicuss:BAAALgAECgcJCwABLgAECgkJVwAHABAlAA==.Annya:BAAALgAECggJCQAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aparajita:BAAALgAECgEJAwABLgABCgMJAwAFAAAAAA==.Aphrodite:BAAALgAECgYJEAAAAA==.',
Aq='Aquda:BAAALgADCgIJBQAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCwAAAA==.Aristoleh:BAAALgAFFAEJAQABLgAFFAkJFAADANgOAA==.Arkahera:BAAALgAECgQJBQABLgAFFAcJFgABAOwZAA==.Aroara:BAAALgAECgEJAQAAAA==.Arolder:BAABLgAECn8mAAMIAAkJqyGABgC4AgAIAAkJdSGABgC4AgAJAAcJZB3dAwA6AgAAAA==.Arredin:BAAALgAECgMJAwAAAA==.Arturium:BAAALgAECgUJBQAAAA==.',
As='Astayuno:BAAALgAECgQJBQAAAA==.',
At='Atabey:BAABLgAECn87AAIKAAkJICIvEQDeAgAKAAkJICIvEQDeAgABLgABCgMJAwAFAAAAAA==.Atimusk:BAAALgADCggJDwABLgAECgYJCgAFAAAAAA==.Atoadaso:BAABLgAECn8hAAILAAgJlh/rAACOAgALAAgJlh/rAACOAgAAAA==.Atretes:BAAALgAECgYJCwAAAA==.Attretes:BAAALgAECgQJCgAAAA==.',
Az='Azazél:BAAALgAECgEJAQABLgAFFAYJFQAHAFELAA==.Azcowboy:BAAALgAECgUJEAAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgAECggJEAAAAA==.',
Ba='Badco:BAAALgAECgQJBAAAAA==.Bairne:BAAALgAECgcJDAABLgAECggJCgAFAAAAAA==.Balacheck:BAABLgAECn8nAAIMAAkJegcsKgCiAAAMAAkJegcsKgCiAAAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barakka:BAAALgAECgEJAQAAAA==.Barecub:BAAALgAECgEJAQABLgAECggJCgAFAAAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAACLgAFFH8HAAMNAAMJlBlQOgCQAAANAAIJXxZQOgCQAAAOAAIJHQ2sJABYAAAuAAQKfywAAg0ACQlwHF4MAJACAA0ACQlwHF4MAJACAAAA.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgYJFAAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAAHAKAcAA==.',
Bi='Bigbadwoof:BAAALgAECgQJCQAAAA==.Bighog:BAACLgAFFH8WAAIEAAUJuiHPDQBSAQAEAAUJuiHPDQBSAQAuAAQKfxgAAwQABwloJmkHAI0CAAQABwloJmkHAI0CAAsAAgkZFB5UAIUAAAAA.Bipbipbup:BAAALgAECgIJAgAAAA==.',
Bj='Björn:BAAALgADCgcJBwAAAA==.',
Bl='Blaazzin:BAAALgAECgMJBgAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Blinck:BAAALgAECgUJCwAAAA==.Blinkz:BAAALgAECgUJBQAAAA==.Bloomzy:BAACLgAFFH8SAAIHAAcJ/hayGACoAQAHAAcJ/hayGACoAQAuAAQKfy4AAwcACQluGoc1AEMCAAcACQluGoc1AEMCAA8AAgl6G1oKAJ8AAAAA.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAABLgAFFH8FAAIGAAMJGQM/CQC1AAAGAAMJGQM/CQC1AAAAAA==.Boombástic:BAABLgAECn8oAAMNAAkJaQ8rLQBwAQANAAgJMhArLQBwAQAOAAIJ0A/fpgBlAAAAAA==.Boomco:BAABLgAECn8uAAIMAAkJ0BFZDwBwAQAMAAkJ0BFZDwBwAQAAAA==.Boomtothekin:BAAALgAECgIJAgABLgAFFAMJDQAKAHQUAA==.Bootes:BAAALgAECgMJAwAAAA==.Bors:BAAALgADCggJEAAAAA==.Boulderholdr:BAABLgAECn8VAAQQAAcJpg00FQCYAAAQAAcJ6ww0FQCYAAALAAEJQwxDfwAqAAAEAAEJ+QYsFwAaAAAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Bravillius:BAABLgAECn8bAAMRAAYJ4gWaKwCBAAARAAYJ4gWaKwCBAAAIAAMJOQA5HQAUAAAAAA==.Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAABLgAECn8dAAISAAkJ2xCcBABQAQASAAkJ2xCcBABQAQAAAA==.Brightburn:BAAALgAECgcJBwAAAA==.Broadside:BAAALgAECgYJBgAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAISAAkJyRmeCgAkAgASAAkJyRmeCgAkAgAAAA==.Bryda:BAAALgAECgYJEAAAAA==.',
Bu='Bubblecreep:BAAALgAECgQJAwABLgAFFAQJCQAEAGwcAA==.Bubblez:BAAALgAECggJCgAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAABLgAECn8aAAIBAAgJaQ1gCACnAAABAAgJaQ1gCACnAAAAAA==.',
Ca='Cajbo:BAABLgAECn89AAIGAAkJViHdAQDbAgAGAAkJViHdAQDbAgAAAA==.Calyssa:BAABLgAECn8eAAIKAAgJ6w5AjQBXAQAKAAgJ6w5AjQBXAQAAAA==.Candyflöss:BAACLgAFFH8JAAIEAAQJbBxHEwALAQAEAAQJbBxHEwALAQAuAAQKfyIAAwQABwmTIsMOAP8BAAQABwmTIsMOAP8BAAsAAQkLEER5ADAAAAAA.Capmkrunch:BAAALgAECgEJAwABLgAECggJEgAFAAAAAA==.Caraling:BAAALgAECgMJBgAAAA==.Caralynn:BAAALgAECgUJEAAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAACLgAFFH8HAAITAAQJJhTfLwD3AAATAAQJJhTfLwD3AAAuAAQKf0QAAhMACQkbIdAFAEoDABMACQkbIdAFAEoDAAAA.Castisteus:BAAALgAECgYJCwAAAA==.Cathelina:BAAALgAECgEJAQAAAA==.Cathom:BAAALgAECgUJCgAAAA==.',
Ch='Charcasm:BAAALgAECgYJCAAAAA==.Charizaard:BAAALgAECgYJCQAAAA==.Charizaardx:BAACLgAFFH8ZAAMUAAcJrwxKAgAUAQAUAAUJvhFKAgAUAQAVAAUJqwPWNQDsAAAuAAQKf1IAAxQACQkdHDMEADgCABQACQlUGzMEADgCABUACAnRFPYlAI0BAAAA.Chevytron:BAAALgAECgYJEwAAAA==.Chomski:BAAALgAECgEJAQAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8fAAMQAAgJEQ99XgDaAAAQAAYJYQ99XgDaAAAEAAQJhwswDQBsAAAAAA==.Clives:BAAALgAECgEJAQAAAA==.Clmx:BAAALgADCgIJAgAAAA==.Clément:BAAALgADCgUJBgAAAA==.',
Co='Coffeebeans:BAABLgAECn8iAAMOAAgJExbjPgCnAQAOAAcJfxTjPgCnAQANAAgJwAt9NgA8AQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowdeath:BAAALgAECgEJAQAAAA==.Cowkiller:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgYJDgAAAA==.Creslan:BAAALgAECgYJBgABLgAECgkJbAAWADgfAA==.Crimsonthot:BAAALgAECggJDQAAAA==.Crogan:BAABLgAECn8VAAQXAAkJzAgNNgApAQAXAAgJJwkNNgApAQAYAAYJcQiHXAClAAAZAAEJ+gVAWgAuAAAAAA==.Crysiscane:BAAALgADCgYJBQAAAA==.Crystalys:BAAALgAECgEJAQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgcJCAABLgAECggJEgAFAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgAECgcJCAAAAA==.Dagul:BAAALgAECgcJCwAAAA==.Dahgrimza:BAAALgAECgUJBQABLgAECgYJCwAFAAAAAA==.Dalna:BAABLgAECn86AAITAAkJShnJEgCHAgATAAkJShnJEgCHAgAAAA==.Danilex:BAABLgAECn8cAAIHAAgJCx9pSABeAgAHAAgJCx9pSABeAgABLgAFFAkJSAAZAHYaAA==.Danksoul:BAAALgAECgkJAQABLgAECgkJDQAFAAAAAA==.Darat:BAAALgADCgEJAQAAAA==.Darcorin:BAABLgAECn8fAAIRAAgJIBbfcACDAQARAAgJIBbfcACDAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAABLgAECn8gAAIMAAkJPAxPFAA1AQAMAAkJPAxPFAA1AQAAAA==.Darksaber:BAABLgAECn8bAAINAAcJQwxFFACEAAANAAcJQwxFFACEAAAAAA==.Dasthodan:BAAALgAECggJCwAAAA==.Dayne:BAAALgAECgcJDQAAAA==.',
Dc='Dctrpepper:BAAALgAECgYJCAAAAA==.',
De='Deathby:BAAALgAECgIJAgAAAA==.Deathcore:BAAALgAECgIJAgAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathtardza:BAABLgAECn8jAAMRAAcJcx0+BgADAgARAAcJcx0+BgADAgAJAAQJnATIKQCGAAAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8xAAQNAAkJJQQPRgD0AAANAAkJJQQPRgD0AAAOAAkJHAYWbQDtAAAaAAIJhQCIOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Delvisprezly:BAAALgAECggJEgAAAA==.Demonica:BAABLgAECn8yAAQbAAkJwgm9AwATAQAbAAkJqgi9AwATAQAcAAUJ4gYqRADmAAAdAAIJwwxf8QBdAAAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Denastus:BAAALgAECgUJBQAAAA==.Dethknyght:BAAALgAECgkJCgABLgAFFAcJFgABAOwZAA==.Detoxin:BAAALgAECgIJAgAAAA==.Devick:BAAALgAECgEJAQAAAA==.',
Di='Dinta:BAABLgAECn9ZAAIKAAkJNx1GHACbAgAKAAkJNx1GHACbAgAAAA==.Dionysys:BAAALgAECgEJAgABLgABCgMJAwAFAAAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAABLgAECn8uAAIMAAkJpx39BQA7AgAMAAkJpx39BQA7AgAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgAECgMJAwAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8fAAIBAAkJLhX1FgDyAQABAAkJLhX1FgDyAQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8sAAIeAAkJTg0oGgDOAQAeAAkJTg0oGgDOAQAAAA==.Dummblond:BAACLgAFFH8XAAMOAAQJXBD3EwDaAAAOAAQJXBD3EwDaAAANAAIJMwU9RQBiAAAuAAQKfyQAAw4ACQkxEYE7AKYBAA4ACQkxEYE7AKYBAA0ACAmlCywRAKgAAAAA.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAABLgAECn8XAAIfAAcJKB0vUgClAQAfAAcJKB0vUgClAQAAAA==.',
Dy='Dyonesa:BAAALgAECgUJBQAAAA==.Dysfunction:BAABLgAECn8XAAIgAAkJeRBfHgBaAQAgAAkJeRBfHgBaAQAAAA==.',
Ea='Earthshield:BAAALgAECgcJDgABLgAFFAIJBQAKAGkHAA==.',
Eg='Ego:BAABLgAECn8iAAIhAAkJPyLXBQAyAwAhAAkJPyLXBQAyAwAAAA==.',
El='Elipto:BAAALgAECgYJBgAAAA==.Ellaana:BAAALgAECgUJEAAAAA==.Elotarra:BAAALgAECgEJAQAAAA==.Elowentinsel:BAAALgAECgEJAQAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgAECgMJAwAAAA==.',
En='Enduran:BAAALgAECgYJDQAAAA==.',
Er='Erasi:BAABLgAECn8zAAMYAAkJVApXLQBtAQAYAAkJVApXLQBtAQAXAAUJzwJXXgBhAAAAAA==.',
Es='Es:BAABLgAECn8UAAIRAAcJ8wTGpgA0AQARAAcJ8wTGpgA0AQAAAA==.Escanorlion:BAAALgADCgcJBwAAAA==.Esileda:BAAALgAECgQJBAAAAA==.Esttsumi:BAAALgAECgkJDwAAAA==.',
Eu='Euphia:BAAALgAECgUJDAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn82AAIMAAkJBRHNDQCGAQAMAAkJBRHNDQCGAQAAAA==.Exodiá:BAAALgAECgYJCwAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8zAAIKAAkJeR1ZIQCBAgAKAAkJeR1ZIQCBAgAAAA==.Faethe:BAAALgAECgYJBwABLgAECgkJVwAHABAlAA==.Faithfulpain:BAAALgADCgYJBgAAAA==.Fananabanana:BAAALgAECgEJAQABLgAFFAMJBQAGABkDAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farmerpolly:BAAALgADCgYJCQAAAA==.Farwolf:BAABLgAECn8oAAIMAAgJWAoVdgBTAQAMAAgJWAoVdgBTAQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECggJBwABLgAFFAMJDQARABoZAA==.Fee:BAACLgAFFH8iAAIKAAcJThuADACtAQAKAAcJThuADACtAQAuAAQKfz4AAgoACQkVJVYIACgDAAoACQkVJVYIACgDAAAA.Fellyn:BAAALgAECgQJBgAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgAECgMJAwAAAA==.Festerr:BAAALgADCgQJAQAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.Fishstick:BAAALgAECgkJDQAAAA==.',
Fl='Flameheart:BAABLgAECn8eAAMiAAgJ5QuFEwAVAQAiAAgJ5QuFEwAVAQAfAAEJAALtaAEPAAAAAA==.Fleathulhu:BAACLgAFFH8VAAIXAAMJzhlWDQDNAAAXAAMJzhlWDQDNAAAuAAQKfzQAAhcACQn0HV4HAPkCABcACQn0HV4HAPkCAAAA.Flungpu:BAAALgAECgUJDwABLgAECgkJPwAMAJoVAA==.',
Fo='Foleigh:BAAALgAECgEJAQAAAA==.Fostock:BAABLgAECn8+AAMfAAkJ8hPOBQDUAQAfAAkJ8hPOBQDUAQAiAAEJvRI0PgA0AAAAAA==.Foxieshoxie:BAAALgAECgEJAwABLgAECggJEgAFAAAAAA==.Foxylocksy:BAAALgAECgQJBAAAAA==.',
Fr='Freeman:BAAALgAECgkJCwAAAA==.Frontierland:BAAALgADCgcJDQAAAA==.Frostdoom:BAAALgAECgQJBQAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgAECgYJBwAAAA==.',
Fu='Furgy:BAAALgAECgEJAQAAAA==.Furrfoxsake:BAAALgAECgYJDQABLgAECggJEAAeAJcbAA==.Fuzball:BAAALgADCggJCQAAAA==.Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Galfure:BAAALgADCgYJBgAAAA==.Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAFAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn83AAIGAAkJhRZmBgACAgAGAAkJhRZmBgACAgAAAA==.',
Ge='Genovefa:BAAALgAECgIJAgAAAA==.',
Gh='Ghoulmaxing:BAABLgAFFH8NAAIRAAMJGhlWOwDqAAARAAMJGhlWOwDqAAAAAA==.Ghøulish:BAAALgAECgUJBwABLgAECggJMQAOAFwMAA==.',
Gi='Gimper:BAAALgAECgUJCAAAAA==.',
Gl='Glaistia:BAAALgAECgEJAQAAAA==.Glen:BAAALgAECgUJEAAAAA==.Glowstik:BAAALgAECgQJBAAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.Gormlaîth:BAAALgAECgQJBwABLgAECgYJCgAFAAAAAA==.Gouki:BAAALgAECgYJBgABLgAECggJJgAKAM4cAA==.',
Gr='Grabmymelonz:BAAALgAECgUJBQAAAA==.Graeman:BAAALgADCgMJAwAAAA==.Grandpaslay:BAAALgAECgQJCQAAAA==.Greatpàw:BAAALgAECgEJAQAAAA==.Grisly:BAAALgADCgUJBQAAAA==.',
Gu='Gurrney:BAAALgAECgMJBgAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAABLgAECn8VAAIDAAYJuglRFwB5AAADAAYJuglRFwB5AAAAAA==.Habbypallie:BAAALgAECgMJAwAAAA==.Haimanist:BAABLgAECn8ZAAISAAgJliAlAwDwAgASAAgJliAlAwDwAgABLgAFFAcJFgABAOwZAA==.Halixan:BAABLgAECn8gAAIjAAkJWyPxAgDiAgAjAAkJWyPxAgDiAgAAAA==.Handlebardoc:BAACLgAFFH8RAAIRAAQJtRpSMwADAQARAAQJtRpSMwADAQAuAAQKf0AAAhEACQleIoISANoCABEACQleIoISANoCAAAA.Harmoni:BAAALgAECgcJCQABLgAECgkJVwAHABAlAA==.Hatorade:BAAALgAECgUJBQAAAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgAECgkJBQAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hellgrin:BAAALgAECgEJAQAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgkJEQAAAA==.',
Ho='Holyname:BAAALgAECgQJAwAAAA==.Holysim:BAAALgAECgEJAQAAAA==.Honir:BAABLgAECn8tAAMSAAgJECApAQB8AgASAAgJECApAQB8AgAKAAYJixBSGgD9AAAAAA==.',
Hu='Hunteð:BAAALgAECgEJAgAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ih='Ihlyria:BAAALgAECgYJBgABLgAECgkJVwAHABAlAA==.',
Ij='Ijillien:BAAALgAECgIJAgAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8yAAMiAAkJHwwvFgD2AAAfAAkJ0AjMcQBWAQAiAAYJGw4vFgD2AAAAAA==.',
In='Infaust:BAAALgADCgEJAQAAAA==.',
Ir='Ireus:BAAALgAECgIJAgAAAA==.Ironfizt:BAAALgAECggJDwABLgAECgkJKAAkAIUYAA==.',
Is='Islet:BAAALgAECgEJAQAAAA==.Istia:BAAALgADCgUJBQAAAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.Itzchris:BAAALgAECgEJAQAAAA==.',
Iu='Iudex:BAAALgAECgkJEQAAAA==.Iutu:BAAALgAECgUJBQAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jacorius:BAAALgADCgIJAgAAAA==.Jamus:BAACLgAFFH8FAAMKAAIJaQcXUAByAAAKAAIJaQcXUAByAAAhAAIJsg1yPgBnAAAuAAQKfz8AAyEACQk3JEUCAFgDACEACQk3JEUCAFgDAAoACAlFD6CEAGYBAAAA.Jarvy:BAAALgAECggJCAAAAA==.',
Je='Jedavon:BAAALgAECgEJAQAAAA==.Jenhadin:BAAALgAECgkJDQAAAA==.Jerreden:BAAALgADCgYJBgAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.Jestic:BAABLgAECn8sAAIkAAkJJBUFAwC6AQAkAAkJJBUFAwC6AQAAAA==.',
Ji='Jiangshi:BAAALgAECgYJCgAAAA==.Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ju='Justpwnedu:BAAALgAECgkJCgAAAA==.',
Ka='Kaazel:BAABLgAECn8/AAIMAAkJmhWCDACaAQAMAAkJmhWCDACaAQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaladiin:BAAALgAECgEJAQAAAA==.Kaldor:BAAALgAECgYJEgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgAECggJEwAAAA==.Kamsham:BAAALgAECgQJBgABLgAECgkJKQABADAYAA==.Kandiquake:BAAALgAECgIJAgAAAA==.Karea:BAAALgAECgcJDgAAAA==.Karite:BAABLgAECn80AAIlAAkJ/iKCAQDgAgAlAAkJ/iKCAQDgAgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAITAAgJRxnIHgAjAgATAAgJRxnIHgAjAgAAAA==.Karveila:BAAALgAECgQJBAAAAA==.Karzyheals:BAAALgADCgEJAQAAAA==.Katyla:BAAALgAECgUJBQABLgAECgkJMwAMAOoMAA==.Kazar:BAAALgADCgcJDwAAAA==.Kazenoth:BAABLgAECn8rAAMVAAkJxxreFwAYAgAVAAkJxxreFwAYAgAmAAEJbxFuPAAyAAAAAA==.',
Ke='Kellement:BAAALgAECgUJBQAAAA==.Ken:BAABLgAECn8gAAINAAgJnRjRBQCAAQANAAgJnRjRBQCAAQABLgAECggJJgAKAM4cAA==.Kennychaoss:BAABLgAECn86AAMCAAkJEx6hDQDpAgACAAkJEx6hDQDpAgADAAcJZw37RwAUAQAAAA==.Kennykaos:BAAALgAECgQJBwAAAA==.Kennykaoss:BAAALgAECgYJCQAAAA==.',
Kh='Khons:BAAALgAECgMJAwAAAA==.Khrisbkreme:BAAALgAECgYJBwABLgAECggJEgAFAAAAAA==.',
Ki='Killatreez:BAAALgAFFAgJAgAAAA==.Kille:BAABLgAECn8gAAIMAAkJHRd1OAD8AQAMAAkJHRd1OAD8AQAAAA==.Killi:BAAALgAECgQJCAAAAA==.Killyoualot:BAAALgADCgcJCgAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Kobebrÿant:BAAALgAECgYJDAAAAA==.Kobeqt:BAAALgAECgYJCQAAAA==.Koland:BAABLgAECn8fAAIXAAkJiQU/CwDjAAAXAAkJiQU/CwDjAAAAAA==.Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn84AAINAAkJXQ4hJwCVAQANAAkJXQ4hJwCVAQAAAA==.Kostazu:BAABLgAECn99AAIDAAkJnRbNAwDvAQADAAkJnRbNAwDvAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAFFAcJIgAKAE4bAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAFFAMJFQAXAM4ZAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.Kyouhei:BAAALgAECgYJBgAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAgABLgAECgMJBgAFAAAAAA==.',
La='Laity:BAABLgAECn9dAAIKAAkJcCGoCgARAwAKAAkJcCGoCgARAwAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Laraithe:BAAALgADCgEJAQAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgAECgEJAQAAAA==.Lazraar:BAAALgAECgEJAQAAAA==.Lazylaz:BAABLgAECn8vAAIaAAkJNyQ5AgAKAwAaAAkJNyQ5AgAKAwABLgAFFAkJLQARAGIfAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAABLgAECn9XAAIjAAgJJiObAAC8AgAjAAgJJiObAAC8AgAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJCQAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAABLgAECn82AAMcAAkJkxt+AgAtAgAcAAkJ9Bp+AgAtAgAdAAgJCA8ZbABMAQAAAA==.Lifebloom:BAAALgAECgIJAgABLgAFFAIJBQAKAGkHAA==.Lightbrew:BAAALgAECgEJAQAAAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAFFAMJCwAeAEYhAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8zAAIMAAkJ6gyKVACmAQAMAAkJ6gyKVACmAQAAAA==.Livedcargox:BAAALgAECgYJBgAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Loqir:BAAALgAFFAIJAwABLgAFFAkJIgAVAA4ZAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Lunariss:BAAALgAECgIJAgABLgAECgYJBwAFAAAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgAECgEJAQAAAA==.',
Ly='Lycanbyte:BAABLgAECn8dAAIGAAYJ0gXqBACHAAAGAAYJ0gXqBACHAAAAAA==.Lylith:BAABLgAECn82AAMcAAkJLBdPEgAIAgAcAAkJLBdPEgAIAgAdAAQJawXT7QBiAAAAAA==.Lyphiandraa:BAAALgAECgEJAQAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJCAAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Maddicollins:BAAALgAECgcJEgABLgAFFAIJDgAKAP0dAA==.Magdalena:BAABLgAECn8+AAIMAAkJ1w8fSADJAQAMAAkJ1w8fSADJAQAAAA==.Magehawk:BAAALgAECgUJBQAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magmaface:BAAALgAECgkJEQAAAA==.Magnólia:BAABLgAECn8vAAICAAkJsyLqCAAjAwACAAkJsyLqCAAjAwAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Maithre:BAAALgAECgIJAwAAAA==.Makima:BAAALgADCgcJCQABLgAFFAQJDQAfAFcXAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Manxgina:BAAALgAECgUJCAABLgAFFAUJFgAVAKIRAA==.Maribelle:BAABLgAECn8ZAAIHAAgJPyRMAwDJAgAHAAgJPyRMAwDJAgABLgAECgkJVwAHABAlAA==.Marrent:BAAALgAECgMJBQAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJDAAAAA==.Mazeltov:BAABLgAECn8WAAIEAAgJPRrNDgAcAgAEAAgJPRrNDgAcAgAAAA==.',
Me='Melomel:BAABLgAECn84AAIjAAkJExo2AQA2AgAjAAkJExo2AQA2AgAAAA==.Melonsquezer:BAABLgAECn83AAMSAAkJsh7eBQCOAgASAAkJsh7eBQCOAgAKAAEJ2RPeMwE9AAAAAA==.Menmei:BAABLgAECn89AAIMAAkJHRdOCADzAQAMAAkJHRdOCADzAQAAAA==.Mexicanrage:BAAALgADCgQJBAAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgAECgUJEAAAAA==.Minien:BAABLgAECn82AAMjAAkJdB2dCwD7AQAjAAgJIR2dCwD7AQADAAgJeRjjIwDHAQAAAA==.Minko:BAABLgAECn8rAAIMAAkJIhsxIABmAgAMAAkJIhsxIABmAgAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAFFAYJFQAHAFELAA==.',
Mo='Moa:BAAALgAECgYJBgABLgAFFAYJFQAHAFELAA==.Modelo:BAAALgAFFAEJAQAAAA==.Molulu:BAAALgADCgcJCwABLgAECgkJJQAHAJ8KAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn9sAAIWAAkJOB+mAgC/AgAWAAkJOB+mAgC/AgAAAA==.Morillic:BAABLgAECn8YAAQnAAcJqxhwCwCmAQAnAAcJqxhwCwCmAQAiAAMJrA0MSACWAAAfAAIJMxSCCgFIAAABLgAECggJGgAYABgWAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgAECgEJAQAAAA==.',
Ms='Mstrcrowly:BAABLgAECn8xAAMfAAgJqiBtFgCdAgAfAAgJqiBtFgCdAgAnAAIJvhwqOgBAAAAAAA==.',
Mu='Mustachjones:BAABLgAECn81AAIfAAkJERxUIABjAgAfAAkJERxUIABjAgAAAA==.',
My='Myros:BAABLgAECn86AAMHAAkJfBbeQwAQAgAHAAkJfBbeQwAQAgAPAAEJ8gWrFQApAAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Nadiaa:BAAALgADCgYJBgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgAECgcJDAAAAA==.Narestor:BAACLgAFFH8IAAIQAAIJdA2EJgCIAAAQAAIJdA2EJgCIAAAuAAQKfxgAAhAACAkdE8ExAOUBABAACAkdE8ExAOUBAAEuAAUUBwkWABUAewoA.Nasril:BAAALgAECggJEgAAAA==.Natallica:BAAALgAECgkJCQAAAA==.Nazervis:BAAALgAECgUJBQABLgAFFAkJLQARAGIfAA==.Nazurend:BAABLgAECn8rAAMHAAkJDBVVRgAIAgAHAAkJDBVVRgAIAgAPAAEJ9QUiFgAmAAAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAFFAIJBAAAAA==.Nemesîs:BAAALgADCgkJGwAAAA==.Nero:BAABLgAECn8nAAIcAAkJTyFYCACoAgAcAAkJTyFYCACoAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.Newhealer:BAAALgADCgEJAQABLgAFFAMJBQAGABkDAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMfAAgJNAUjfQBhAQAfAAgJNAUjfQBhAQAiAAIJywFjZgBDAAAAAA==.Nimpopstar:BAAALgAECgEJAQAAAA==.Nimuerose:BAAALgAECgEJAQAAAA==.',
No='Noah:BAAALgAECggJEAAAAA==.Noint:BAAALgAECgQJBAAAAA==.Nortree:BAABLgAECn86AAIOAAkJixOeBgB0AQAOAAkJixOeBgB0AQAAAA==.Nost:BAABLgAECn8sAAIKAAgJDhyQQAAFAgAKAAgJDhyQQAAFAgAAAA==.Notalock:BAAALgADCgIJAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.Novena:BAAALgAECgQJBAABLgAECgkJLwACALMiAA==.',
Nu='Nulwyrm:BAABLgAECn8sAAMVAAkJQBuAEABjAgAVAAkJQBuAEABjAgAUAAEJohhQIQBKAAAAAA==.Numira:BAAALgADCgMJAwAAAA==.',
Ny='Nymue:BAAALgAECgMJBAAAAA==.Nyyrivik:BAAALgAECgYJCgAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8tAAICAAgJRR+rGACEAgACAAgJRR+rGACEAgAAAA==.',
Oh='Ohitsadragon:BAACLgAFFH8HAAIUAAIJSwtECgCCAAAUAAIJSwtECgCCAAAuAAQKfycAAhQACQkvGSgBALUBABQACQkvGSgBALUBAAAA.',
On='Ono:BAAALgAECgEJAQAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAFAAAAAA==.Oreoscruunit:BAAALgAECgYJBwABLgAECggJEgAFAAAAAA==.',
Ow='Owl:BAABLgAECn8fAAInAAkJAwxUDQBgAQAnAAkJAwxUDQBgAQAAAA==.Owlcatraz:BAACLgAFFH8UAAMNAAYJvQ8DEQAEAQANAAUJCg8DEQAEAQAOAAUJgwcHLwD2AAAuAAQKfxUAAw0ACAlXGv4ZAPwBAA0ACAlXGv4ZAPwBAA4ABQknC5Z3AM8AAAAA.',
Pa='Paendrag:BAAALgAECgYJCgAAAA==.Paladinna:BAAALgAECgIJAgAAAA==.Panadarama:BAACLgAFFH8WAAIBAAcJ7BlwCgDqAQABAAcJ7BlwCgDqAQAuAAQKfygAAgEACAkeJWgEAEUDAAEACAkeJWgEAEUDAAAA.Pandmei:BAAALgADCgkJCQAAAA==.Panteragon:BAABLgAECn82AAIeAAkJAAt+AwBuAQAeAAkJAAt+AwBuAQAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAABLgAECn81AAIMAAkJChJECwCvAQAMAAkJChJECwCvAQAAAA==.Patina:BAAALgAECggJCwABLgAECgkJXQAKAHAhAA==.',
Pe='Peachyboy:BAAALgADCgMJAwAAAA==.Periwinkle:BAABLgAECn8eAAIXAAgJZg/SKACAAQAXAAgJZg/SKACAAQAAAA==.Persaud:BAACLgAFFH8ZAAMnAAYJzhSCCADxAAAfAAYJ0BKJSwAwAQAnAAMJwRWCCADxAAAuAAQKfxwAAyIACQkkGtsPANEBACIABwmeEtsPANEBAB8ABQn0Hm1RAKcBAAAA.Peterbilt:BAAALgAECgQJBQAAAA==.',
Ph='Phidra:BAABLgAECn9FAAMCAAkJIw/9OwC/AQACAAkJIw/9OwC/AQADAAQJTga/agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgAECgkJJQAHAJ8KAA==.Phranky:BAAALgAECgEJBAABLgAECggJEgAFAAAAAA==.Phytos:BAAALgAECgEJAQAAAA==.',
Pi='Pixiebrew:BAAALgAECgUJDgAAAA==.Pizzagirl:BAAALgAECgYJEgAAAA==.',
Pl='Plutrax:BAAALgAECggJEgAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.Poprocks:BAABLgAECn8bAAIfAAgJKhvsAwAzAgAfAAgJKhvsAwAzAgAAAA==.Power:BAAALgAECgEJAQAAAA==.',
Pr='Predatorc:BAABLgAECn8dAAIMAAkJaArHTgB9AQAMAAkJaArHTgB9AQAAAA==.Prepotêntê:BAAALgAECgYJCgAAAA==.Primevil:BAABLgAECn82AAIKAAgJzxkuBwAJAgAKAAgJzxkuBwAJAgAAAA==.Primevl:BAABLgAECn8zAAQaAAgJgRl9AgCrAQAaAAgJwhh9AgCrAQANAAgJeRS+BACpAQAgAAYJUhAfCQDwAAAAAA==.Primévil:BAABLgAECn83AAIdAAkJ5g40WQB8AQAdAAkJ5g40WQB8AQAAAA==.',
Pu='Puffon:BAAALgADCgMJBQAAAA==.Puma:BAABLgAECn8VAAQOAAYJjgKksQBWAAAOAAYJjgKksQBWAAANAAMJjwEQdwBHAAAgAAIJ0gGHjAASAAAAAA==.',
Py='Pymipalmdale:BAAALgAECgEJAQAAAA==.Pyrissa:BAAALgADCgEJAQAAAA==.',
['Pí']='Píp:BAAALgADCggJDQAAAA==.',
Qu='Quarz:BAAALgAECgMJBAAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.Quoternion:BAAALgAECgEJAQABLgAFFAQJBwATACYUAA==.',
Ra='Raden:BAAALgAECgQJBQAAAA==.Raediant:BAAALgAECgUJBwABLgAECgkJHwABAC4VAA==.Raelek:BAAALgAECgQJBAAAAA==.Ragethecage:BAAALgAECgEJAQAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Ragsonfire:BAAALgADCgIJAgAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8lAAMQAAgJPByjHQABAgAQAAgJPByjHQABAgAEAAcJrRS7HgA9AQAAAA==.Raquel:BAABLgAECn8jAAICAAkJJQtvRwBkAQACAAkJJQtvRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAABLgAECn8QAAIeAAgJlxs9DQBSAgAeAAgJlxs9DQBSAgAAAA==.',
Re='Rectaltremor:BAAALgADCgIJAgAAAA==.Rede:BAAALgAECgIJAwAAAA==.Reeyou:BAABLgAECn8mAAIKAAgJzhytBQBBAgAKAAgJzhytBQBBAgAAAA==.Reign:BAACLgAFFH8VAAIHAAYJUQvEIwBNAQAHAAYJUQvEIwBNAQAuAAQKf04AAgcACQkZHMckAIkCAAcACQkZHMckAIkCAAAA.Reilu:BAAALgADCgIJAgAAAA==.Relieff:BAABLgAECn8YAAIcAAgJIAn2PgC6AAAcAAgJIAn2PgC6AAAAAA==.Relmin:BAAALgAECgEJAQAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.Revalz:BAAALgAECggJCAAAAA==.Revival:BAAALgAECgYJBwABLgAFFAIJBQAKAGkHAA==.Rewdruid:BAAALgAECgEJAQAAAA==.Reynax:BAAALgAECgEJAQAAAA==.',
Ri='Rio:BAABLgAECn9SAAIcAAkJlB8/BgDUAgAcAAkJlB8/BgDUAgAAAA==.Ris:BAABLgAECn84AAIHAAkJtB/vGADEAgAHAAkJtB/vGADEAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgAECgMJAwAAAA==.Rockyrogue:BAABLgAECn8fAAIkAAgJDQe0MwAKAQAkAAgJDQe0MwAKAQAAAA==.Roknathar:BAABLgAECn8xAAMWAAkJyCXRAgC3AgAWAAgJwSXRAgC3AgAMAAMJ4R4TmgANAQAAAA==.Rolldemort:BAAALgAECgIJAwABLgAECggJEgAFAAAAAA==.Ronburrgandy:BAAALgAECgEJAQAAAA==.Ronilf:BAABLgAECn8oAAIkAAkJhRjHFwDcAQAkAAkJhRjHFwDcAQAAAA==.Rono:BAAALgAECgMJBAAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8oAAMYAAkJURxoFAAqAgAYAAkJURxoFAAqAgAXAAIJyhN8iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgAECgcJCAAAAA==.Rukaza:BAAALgAECgEJAQABLgAFFAYJFQAdAH8ZAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Sabrilla:BAAALgAECgQJAwAAAA==.Saerenity:BAAALgAECgMJAwAAAA==.Sahala:BAAALgADCgEJAQAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgAECgEJAQAAAA==.Sakkra:BAAALgADCgQJBAAAAA==.Sangoma:BAABLgAECn8bAAIjAAgJLBEhAwB+AQAjAAgJLBEhAwB+AQAAAA==.Sapele:BAAALgADCgUJBQAAAA==.Saphihr:BAAALgADCgYJBgAAAA==.Sapultura:BAAALgAECgEJAQAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAFAAAAAA==.',
Se='Sedo:BAABLgAECn8dAAIHAAgJcgg+HADxAAAHAAgJcgg+HADxAAAAAA==.Selenis:BAAALgAECgcJDQABLgAECgkJNwAIAJolAA==.Severs:BAABLgAECn8gAAIQAAgJzg8yBwBjAQAQAAgJzg8yBwBjAQAAAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowmonarc:BAABLgAECn8VAAIRAAkJWA41DwA6AQARAAkJWA41DwA6AQAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shadygrove:BAAALgAECgEJAQABLgAECgkJLwACALMiAA==.Shamainiac:BAABLgAECn9KAAIDAAkJpRmLEwBQAgADAAkJpRmLEwBQAgAAAA==.Shamania:BAAALgAFFAIJAgABLgAFFAQJCQAEAGwcAA==.Shamith:BAAALgAECgcJDgAAAA==.Shammymax:BAAALgADCgkJAQAAAA==.Shaomai:BAACLgAFFH8LAAIDAAQJyhdhJAAHAQADAAQJyhdhJAAHAQAuAAQKfysAAwMACQn1IAYLALACAAMACQn1IAYLALACAAIABAkvDRpzAMMAAAAA.Sharper:BAACLgAFFH8KAAIdAAQJ4xpBOgA8AQAdAAQJ4xpBOgA8AQAuAAQKfxcAAh0ABwlpHGpOAJoBAB0ABwlpHGpOAJoBAAEuAAUUBAkRABEAtRoA.Shep:BAAALgAECgMJAwAAAA==.Sherminator:BAAALgADCgYJBgAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shi:BAAALgAECgQJBAAAAA==.Shifte:BAABLgAECn8ZAAIaAAgJzRKIBAAsAQAaAAgJzRKIBAAsAQAAAA==.Shiok:BAAALgAECgMJAwAAAA==.Shishkademon:BAAALgAECgIJAgAAAA==.Shiv:BAAALgADCgEJAQABLgAECggJFAAQACgXAA==.Shocks:BAAALgAECgYJBgABLgAFFAcJIgAKAE4bAA==.Shoknorris:BAAALgADCgkJCQAAAA==.Shákeera:BAAALgADCgUJBQABLgAECggJFQAdALcNAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgcJDAAAAA==.Silverwin:BAABLgAECn89AAIXAAkJkw9ZCAAuAQAXAAkJkw9ZCAAuAQAAAA==.Sinanath:BAAALgAECgEJAQAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8lAAIoAAkJRRpZAgA5AgAoAAkJRRpZAgA5AgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smashufacein:BAAALgAECgkJAwAAAA==.Smite:BAAALgAECgQJDgAAAA==.Smitted:BAABLgAECn8cAAMKAAcJ1RC0sgAbAQAKAAcJoAy0sgAbAQASAAcJfQ1XIwDtAAAAAA==.Smittens:BAAALgAECgUJBQAAAA==.Smitty:BAABLgAECn8XAAMBAAgJnhWlIgCUAQABAAgJeBSlIgCUAQApAAgJQxD6LABZAQAAAA==.',
Sn='Snakmag:BAAALgAFFAIJAwAAAA==.Snykkers:BAAALgADCgUJBQABLgAECgkJPwAMAJoVAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAABLgAECn8iAAMhAAYJohkcBgB7AQAhAAYJohkcBgB7AQAKAAYJMQ6BygD6AAAAAA==.Sophiaa:BAAALgAECgUJCQAAAA==.Sorn:BAABLgAECn89AAISAAkJIhSEAwCPAQASAAkJIhSEAwCPAQAAAA==.',
Sp='Spaarkle:BAAALgAECgkJEQAAAA==.Specialheist:BAABLgAECn8bAAIXAAkJ1QKySgC5AAAXAAkJ1QKySgC5AAAAAA==.Spectrehawk:BAABLgAFFH8FAAISAAMJZQjVCQB1AAASAAMJZQjVCQB1AAABLgAFFAYJGgAIANchAA==.Speçtre:BAACLgAFFH8aAAIIAAYJ1yERDgCdAQAIAAYJ1yERDgCdAQAuAAQKfy8AAwgACQkNHU0LAFsCAAgACAk0IE0LAFsCABEAAQn+Bi9mAT0AAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgQJBAAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAABLgAECn8aAAIYAAgJGBaAIQC6AQAYAAgJGBaAIQC6AQAAAA==.Stonemace:BAAALgADCgYJBgABLgAECgEJAQAFAAAAAA==.Stormglaive:BAABLgAECn8aAAMcAAcJPxU8HQDWAQAcAAcJPxU8HQDWAQAdAAEJUwPt6QAoAAAAAA==.Strikedark:BAAALgAECgEJAQAAAA==.Stupidity:BAABLgAECn8sAAMYAAgJeB42EwA4AgAYAAgJeB42EwA4AgAXAAIJhBe4WAB3AAAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn9HAAMTAAkJ3x/2BwAdAwATAAkJ3x/2BwAdAwApAAgJRhTHIQChAQAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
Sy='Synterra:BAAALgADCgkJCQAAAA==.Syranda:BAAALgAFFAEJAQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAABLgAECggJEAAeAJcbAA==.',
['Sâ']='Sâintdank:BAAALgAECgkJAgAAAA==.',
Ta='Taara:BAAALgAECgMJBQABLgAECgkJVwAHABAlAA==.Tadlight:BAAALgAECgMJAwAAAA==.Taquìto:BAAALgAECgEJAQAAAA==.Tarok:BAAALgAECggJEQAAAA==.Tarysha:BAABLgAECn8qAAIkAAkJvwlpHQCrAQAkAAkJvwlpHQCrAQAAAA==.Tasathen:BAAALgADCgMJAgAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn80AAIgAAkJ5xDYHgBXAQAgAAkJ5xDYHgBXAQAAAA==.Tayoma:BAAALgAECgEJBQAAAA==.Tazara:BAAALgAECgYJDAAAAA==.',
Te='Tealth:BAAALgAECgYJBgAAAA==.Teapha:BAABLgAECn8UAAMYAAgJVxVJBAC/AQAYAAgJVxVJBAC/AQAZAAEJERhKHwBHAAABLgAECggJJgAKAM4cAA==.Ted:BAABLgAECn8tAAIDAAgJpxgACQAzAQADAAgJpxgACQAzAQAAAA==.Tehgermza:BAAALgAECgcJBwAAAA==.Tehgrimza:BAABLgAECn80AAMfAAkJlBxJHwBpAgAfAAkJlBxJHwBpAgAiAAEJrxCDdAAwAAAAAA==.Teias:BAAALgAECggJCgABLgAFFAYJHAAXAJscAA==.Teka:BAAALgADCgMJAwAAAA==.Temu:BAAALgAECgYJCAABLgAFFAQJDQAfAFcXAA==.Tet:BAACLgAFFH8HAAIOAAMJAQ8lRACjAAAOAAMJAQ8lRACjAAAuAAQKfxkAAg4ACAkyH6QQAMwCAA4ACAkyH6QQAMwCAAAA.Tevia:BAABLgAECn8tAAILAAkJ4xibDQAOAgALAAkJ4xibDQAOAgAAAA==.',
Th='Thalip:BAAALgAECgQJBwAAAA==.Thekingheals:BAAALgAECgUJCAABLgAFFAQJBwApAFsVAA==.Thokmay:BAABLgAECn8rAAIpAAkJPRJHIACrAQApAAkJPRJHIACrAQAAAA==.Thorel:BAAALgAECgQJBwAAAA==.Thornar:BAAALgAECgUJBQAAAA==.Thunden:BAAALgAFFAIJAgAAAA==.Thyeth:BAAALgADCgEJAQAAAA==.',
Ti='Tiandrinna:BAABLgAECn8qAAIPAAkJKxxWAgA+AgAPAAkJKxxWAgA+AgAAAA==.Tianest:BAAALgAECgYJDQAAAA==.Tightywhitey:BAAALgAECgkJEgAAAA==.Tigirius:BAAALgAECgQJBAAAAA==.Timkaoss:BAABLgAECn8pAAMOAAcJ/hjjBwBHAQAOAAcJ/hjjBwBHAQANAAUJyBMYDADoAAAAAA==.Timmychaos:BAAALgAECgQJBAAAAA==.Timmyjudge:BAAALgAECgYJCAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAABLgAECn89AAIEAAkJOAdRBgAEAQAEAAkJOAdRBgAEAQAAAA==.',
To='Toastedoreos:BAAALgAECgEJAQABLgAECggJEgAFAAAAAA==.Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgkJFgAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgQJCAABLgAECgkJLwACALMiAA==.Toyoma:BAAALgADCgEJAQAAAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgAECgUJEQAAAA==.Trixterwolf:BAAALgAECgEJAQAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAACLgAFFH8WAAIHAAUJIhN0LQAWAQAHAAUJIhN0LQAWAQAuAAQKfy0AAgcACQlcGRQ8ACoCAAcACQlcGRQ8ACoCAAAA.',
Ty='Tygrassar:BAAALgAECgIJAgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8wAAIXAAkJVh3mCADaAgAXAAkJVh3mCADaAgAAAA==.',
['Tä']='Täd:BAABLgAECn8fAAIfAAkJExEECQBvAQAfAAkJExEECQBvAQAAAA==.',
Ul='Ulqiuorra:BAAALgADCgQJAQAAAA==.',
Un='Unholycreep:BAAALgAFFAEJAgABLgAFFAQJCQAEAGwcAA==.',
Va='Vaelenka:BAAALgADCgMJAwAAAA==.Vaelune:BAAALgAECgYJBgAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAABLgAECn8kAAMJAAgJ9QvAEwBAAQAJAAgJXAvAEwBAAQARAAYJPAkn0ADoAAAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAACLgAFFH8HAAIKAAMJlQ8edADLAAAKAAMJlQ8edADLAAAuAAQKfyIAAgoACAlXHss8ABECAAoACAlXHss8ABECAAAA.Valiant:BAAALgAECgkJEgAAAA==.Valicous:BAABLgAECn8hAAIWAAYJcQdCBgCcAAAWAAYJcQdCBgCcAAAAAA==.Valyerian:BAABLgAECn8uAAIQAAgJ5hsOFgCcAgAQAAgJ5hsOFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgkJHgAIAGMiAA==.Vandevoker:BAAALgAECgQJCAABLgAECgkJHgAIAGMiAA==.Vanserra:BAAALgADCgcJEAAAAA==.Varregory:BAAALgADCgUJBAAAAA==.Vaxas:BAABLgAECn8jAAIKAAgJ1h/JMgA1AgAKAAgJ1h/JMgA1AgAAAA==.Vaxasus:BAAALgAECgEJAQAAAA==.Vaylorian:BAABLgAECn8VAAIgAAYJFyACEwDDAQAgAAYJFyACEwDDAQAAAA==.Vaült:BAABLgAECn85AAMhAAkJ8hiGDwCgAgAhAAkJ8hiGDwCgAgAKAAMJPwYbEgFzAAAAAA==.',
Ve='Velion:BAAALgAECgUJBgAAAA==.Velystana:BAAALgADCgIJAgAAAA==.Verianna:BAABLgAECn83AAQIAAkJmiVLAQBRAwAIAAkJFSVLAQBRAwARAAgJZyETMAA/AgAJAAUJlhqRDwB9AQAAAA==.Vexmorphis:BAAALgAECgMJBAABLgAECgkJHgAKAJwSAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgAECgQJBAAAAA==.',
Vr='Vraknaar:BAAALgAECgMJAwAAAA==.',
Vt='Vtown:BAAALgAECgMJCQAAAA==.',
Wa='Wadumu:BAABLgAECn8xAAMOAAgJXAwOaQAYAQAOAAYJVg4OaQAYAQAgAAgJlwslLwDwAAAAAA==.Wagwanmist:BAABLgAECn8tAAITAAgJtBmfHQAsAgATAAgJtBmfHQAsAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warrdaddy:BAAALgAECgIJAwAAAA==.Warvegas:BAAALgAECgUJDAAAAA==.Warwulf:BAAALgAECgQJBAABLgAECggJJQAQADwcAA==.Water:BAAALgADCgEJAQAAAA==.',
Wi='Willowy:BAABLgAECn9XAAIHAAkJECWNAgAAAwAHAAkJECWNAgAAAwAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8cAAQCAAUJ4hNKeAD1AAACAAUJ4hNKeAD1AAADAAQJ6wjhfQB3AAAjAAEJngq9PwAxAAAAAA==.',
Xa='Xaerius:BAABLgAECn9HAAMQAAkJEBqfEgBeAgAQAAkJEBqfEgBeAgALAAEJ6wUlhgAjAAAAAA==.Xalatath:BAAALgAECgYJBwAAAA==.Xan:BAABLgAECn8gAAIHAAkJyRfNUQDnAQAHAAkJyRfNUQDnAQAAAA==.Xann:BAAALgAECgIJAgAAAA==.Xannen:BAAALgADCgkJCQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAABLgAECn8iAAMHAAgJViOxAwCuAgAHAAgJSCOxAwCuAgAoAAMJrSAeDAC9AAAAAA==.Xashadin:BAAALgAECgcJBwABLgAECggJDQAFAAAAAA==.Xashae:BAAALgADCgcJDwAAAA==.Xashamorne:BAAALgAECggJDQAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIHAAcJJiNIPQCCAgAHAAcJJiNIPQCCAgAAAA==.',
Xo='Xog:BAAALgAECgIJAgAAAA==.',
Ya='Yarman:BAABLgAECn89AAIBAAkJSh4IAQCDAgABAAkJSh4IAQCDAgAAAA==.',
Ye='Yeaforpie:BAABLgAECn8yAAMnAAkJYRTKAQDDAQAnAAkJYRTKAQDDAQAfAAgJ8Q++XACIAQAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAABLgAECn8YAAIhAAgJ7BQPLACxAQAhAAgJ7BQPLACxAQAAAA==.',
Yo='Yoshial:BAABLgAECn8lAAIHAAkJnwqFHgDgAAAHAAkJnwqFHgDgAAAAAA==.Youfemaledog:BAAALgADCgEJAQAAAA==.',
Za='Zadoc:BAAALgAECgMJAwAAAA==.Zano:BAACLgAFFH8FAAIYAAMJlhLAIwDXAAAYAAMJlhLAIwDXAAAuAAQKfz4AAxgACQlDG1cNAH4CABgACQlDG1cNAH4CABkABgk8DQhCAAIBAAAA.',
Ze='Zealins:BAAALgAECgYJCwAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zerastar:BAAALgAECgQJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQABLgAFFAYJFQAKAMQjAA==.Zirou:BAABLgAFFH8MAAITAAUJlRfQEgBXAQATAAUJlRfQEgBXAQABLgAFFAMJCwAeAEYhAA==.Ziv:BAACLgAFFH8aAAIOAAUJ4xk+GACdAQAOAAUJ4xk+GACdAQAuAAQKfzYAAg4ACQkqINEIACsDAA4ACQkqINEIACsDAAEuAAUUAwkLAB4ARiEA.Ziyn:BAACLgAFFH8LAAIeAAMJRiG7FwAUAQAeAAMJRiG7FwAUAQAuAAQKfxgAAx4ACQk+HmgHAKgCAB4ACQk+HmgHAKgCAAwABgmuGnJ9AEQBAAAA.',
Zo='Zoda:BAAALgAECgQJBgAAAA==.Zombia:BAAALgAECgIJAgAAAA==.',
Zx='Zx:BAAALgAECgEJAQAAAA==.Zxno:BAAALgAECgEJAQAAAA==.Zxolgarai:BAAALgAECgMJBAAAAA==.',
['Ôa']='Ôath:BAAALgAECgEJAQAAAA==.',
['Öw']='Öwlbeback:BAAALgADCgYJBgAAAA==.',
['Ýa']='Ýachiru:BAAALgAECgEJAQAAAA==.',
['Ÿe']='Ÿeñnefer:BAAALgADCgIJAgAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
