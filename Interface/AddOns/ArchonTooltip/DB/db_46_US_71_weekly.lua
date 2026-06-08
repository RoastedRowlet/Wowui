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

local lookup = {'Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Mage-Fire','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Warrior-Arms','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Warlock-Demonology','Druid-Guardian','Warlock-Destruction','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Evoker-Preservation','Warlock-Affliction','Mage-Arcane','Monk-Windwalker',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aarztok:BAAALgAECgUJBQABLgAFFAcJFgABAOwZAA==.',
Ac='Achepir:BAAALgADCgIJAgAAAA==.Achiella:BAAALgAECgEJAQAAAA==.',
Ad='Advisor:BAACLgAFFH8KAAICAAQJkRDHOQDlAAACAAQJkRDHOQDlAAAuAAQKfzQAAwIACQmcJG0JAOECAAIACQmcJG0JAOECAAMAAQl5F3ePAEUAAAAA.',
Ae='Aería:BAAALgAECgYJDwAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgAECgEJAQAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgADCgcJBwAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aldoraine:BAAALgAECgEJAQABLgAECgEJAgAEAAAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgADCgcJEAAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgAECgQJCAAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Andolas:BAAALgADCgYJCQAAAA==.Angelicuss:BAAALgAECgUJBgABLgAECgkJPAAFAL8jAA==.Annya:BAAALgAECgYJBgAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aparajita:BAAALgAECgEJAQABLgABCgMJAwAEAAAAAA==.Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCwAAAA==.Aristoleh:BAAALgADCgUJBQABLgAFFAcJEQADANgOAA==.Arkahera:BAAALgAECgQJBQABLgAFFAcJFgABAOwZAA==.Arolder:BAABLgAECn8mAAMGAAkJqyHdBQDBAgAGAAkJdSHdBQDBAgAHAAcJZB3dAwA6AgAAAA==.Arredin:BAAALgADCgYJBgAAAA==.Arturium:BAAALgADCgYJCwAAAA==.',
As='Astayuno:BAAALgAECgMJAwAAAA==.',
At='Atabey:BAABLgAECn87AAIIAAkJICInDwDjAgAIAAkJICInDwDjAgABLgABCgMJAwAEAAAAAA==.Atimusk:BAAALgADCggJDwABLgAECgQJBwAEAAAAAA==.Atoadaso:BAAALgAECggJDAAAAA==.Attretes:BAAALgADCgcJDwAAAA==.',
Az='Azazél:BAAALgAECgEJAQABLgAFFAMJBQAFAPsKAA==.Azcowboy:BAAALgAECgMJCwAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgAECgMJAwAAAA==.',
Ba='Badco:BAAALgAECgQJBAAAAA==.Balacheck:BAABLgAECn8XAAIJAAYJyARjsgDOAAAJAAYJyARjsgDOAAAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgADCgQJCgAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAABLgAECn8qAAIKAAkJbxyUCwCRAgAKAAkJbxyUCwCRAgAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgYJFAAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAAFAKAcAA==.',
Bi='Bigbadwoof:BAAALgADCgYJIQAAAA==.Bighog:BAACLgAFFH8UAAILAAQJGyEvCwBjAQALAAQJGyEvCwBjAQAuAAQKfxYAAgsABwloJtsGAJACAAsABwloJtsGAJACAAAA.Bipbipbup:BAAALgAECgEJAQAAAA==.',
Bj='Björn:BAAALgADCgcJBwAAAA==.',
Bl='Blaazzin:BAAALgADCgcJHgAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Blinck:BAAALgADCgYJDAAAAA==.Blinkz:BAAALgAECgUJBQAAAA==.Bloomzy:BAACLgAFFH8HAAIFAAMJFiFhYwAZAQAFAAMJFiFhYwAZAQAuAAQKfy4AAwUACQluGpUyAEgCAAUACQluGpUyAEgCAAwAAgl6G1oKAJ8AAAAA.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAAALgAFFAIJAgAAAA==.Boombástic:BAABLgAECn8oAAMKAAkJaQ9GKgBzAQAKAAgJMhBGKgBzAQANAAIJ0A/9nwBnAAAAAA==.Boomco:BAABLgAECn8WAAIJAAgJxQ5NVQCXAQAJAAgJxQ5NVQCXAQAAAA==.Bootes:BAAALgAECgMJAwAAAA==.Bors:BAAALgADCgUJEAAAAA==.Boulderholdr:BAAALgAECgQJCgAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Bravillius:BAAALgADCgcJCwAAAA==.Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAAALgAECgcJEwAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAIOAAkJyRmeCgAkAgAOAAkJyRmeCgAkAgAAAA==.Bryda:BAAALgAECgQJCgAAAA==.',
Bu='Bubblez:BAAALgADCgYJCQAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAAALgAECgUJDwAAAA==.',
Ca='Cajbo:BAABLgAECn86AAIPAAkJ9R+oAQDdAgAPAAkJ9R+oAQDdAgAAAA==.Calyssa:BAABLgAECn8eAAIIAAgJ6w6ChABbAQAIAAgJ6w6ChABbAQAAAA==.Candyflöss:BAACLgAFFH8JAAILAAQJbByTEAAYAQALAAQJbByTEAAYAQAuAAQKfx0AAwsABgkuJMwNAAICAAsABgkuJMwNAAICABAAAQkLEOpwADAAAAAA.Capmkrunch:BAAALgAECgEJAgABLgAECggJDAAEAAAAAA==.Caraling:BAAALgADCgYJBwAAAA==.Caralynn:BAAALgAECgUJDQAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAABLgAECn9EAAIRAAkJGyFBBQBKAwARAAkJGyFBBQBKAwAAAA==.Castisteus:BAAALgAECgYJCAAAAA==.Cathelina:BAAALgADCggJDwAAAA==.Cathom:BAAALgAECgUJCgAAAA==.',
Ch='Charcasm:BAAALgAECgYJCAAAAA==.Charizaard:BAAALgAECgYJCQAAAA==.Charizaardx:BAACLgAFFH8PAAMSAAYJwgj3BgDLAAATAAUJqwNmLwD4AAASAAQJrAz3BgDLAAAuAAQKf0QAAxIACQncGUIEACwCABIACQn1F0IEACwCABMACAnRFPYlAI0BAAAA.Chevytron:BAAALgAECgYJEwAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8bAAMUAAcJSxAPWQDgAAAUAAYJYQ8PWQDgAAALAAMJzgxrQwBWAAAAAA==.Clives:BAAALgAECgEJAQAAAA==.Clmx:BAAALgADCgIJAgAAAA==.Clément:BAAALgADCgUJBgAAAA==.',
Co='Coffeebeans:BAABLgAECn8iAAMNAAgJExbjPgCnAQANAAcJfxTjPgCnAQAKAAgJwAuTMwA8AQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowdeath:BAAALgADCgEJAQAAAA==.Cowkiller:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgYJDgAAAA==.Creslan:BAAALgAECgYJBgABLgAECgkJRwAVALkeAA==.Crimsonthot:BAAALgAECgYJCQAAAA==.Crogan:BAABLgAECn8UAAQWAAkJzAiVMwApAQAWAAgJJwmVMwApAQAXAAUJJAhDVgCuAAAYAAEJ+gVAWgAuAAAAAA==.Crysiscane:BAAALgADCgYJBQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQABLgAECggJDAAEAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgAECgUJBQAAAA==.Dagul:BAAALgAECgcJCwAAAA==.Dalna:BAABLgAECn83AAIRAAkJQxg7EQCFAgARAAkJQxg7EQCFAgAAAA==.Danilex:BAABLgAECn8cAAIFAAgJCx9pSABeAgAFAAgJCx9pSABeAgABLgAFFAgJLgAYALIbAA==.Danksoul:BAAALgAECgkJAQABLgAECggJGAAZAK4ZAA==.Darcorin:BAABLgAECn8fAAIaAAgJIBZJaACOAQAaAAgJIBZJaACOAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAABLgAECn8ZAAIJAAcJMQefiwAaAQAJAAcJMQefiwAaAQAAAA==.Darksaber:BAAALgAECgUJDwAAAA==.Dasthodan:BAAALgAECgMJBgAAAA==.Dayne:BAAALgAECgcJDQAAAA==.',
Dc='Dctrpepper:BAAALgAECgIJAgAAAA==.',
De='Deathcore:BAAALgADCgkJEwAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathtardza:BAAALgAECgQJBAAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8xAAQKAAkJJQTsQQD3AAAKAAkJJQTsQQD3AAANAAkJHAYtaQDvAAAbAAIJhQCIOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Delvisprezly:BAAALgAECggJDAAAAA==.Demonica:BAABLgAECn8nAAQcAAkJ4wdVEQApAQAcAAkJ4wdVEQApAQAdAAUJ4gYqRADmAAAeAAEJtQmHDQEtAAAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Demonspecial:BAAALgAECgkJBwAAAA==.Denastus:BAAALgAECgUJBQAAAA==.Dethknyght:BAAALgAECgkJCgABLgAFFAcJFgABAOwZAA==.Detoxin:BAAALgAECgIJAgAAAA==.Devick:BAAALgAECgEJAQAAAA==.',
Di='Dinta:BAABLgAECn9QAAIIAAkJ5BuwGQCfAgAIAAkJ5BuwGQCfAgAAAA==.Dionysys:BAAALgAECgEJAQABLgABCgMJAwAEAAAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAABLgAECn8WAAIJAAgJFxiVNQD7AQAJAAgJFxiVNQD7AQAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgAECgMJAwAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8fAAIBAAkJLhXuFQD0AQABAAkJLhXuFQD0AQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8sAAIfAAkJTg1gGADaAQAfAAkJTg1gGADaAQAAAA==.Dummblond:BAACLgAFFH8MAAMNAAQJFQRpPgCvAAANAAQJFQRpPgCvAAAKAAEJKwSlTAAvAAAuAAQKfx4AAw0ACAlrEVE5AKcBAA0ACAlrEVE5AKcBAAoABwkxCGxZAL4AAAAA.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAABLgAECn8XAAIgAAcJKB2XTwCoAQAgAAcJKB2XTwCoAQAAAA==.',
Dy='Dyonesa:BAAALgAECgUJBQAAAA==.Dysfunction:BAABLgAECn8UAAIhAAgJwREcHABaAQAhAAgJwREcHABaAQAAAA==.',
Ea='Earthshield:BAAALgAECgYJDQABLgAECgkJPwAZADckAA==.',
Eg='Ego:BAABLgAECn8iAAIZAAkJPyI7BQA1AwAZAAkJPyI7BQA1AwAAAA==.',
El='Elipto:BAAALgAECgYJBgAAAA==.Ellaana:BAAALgAECgUJEAAAAA==.Elotarra:BAAALgAECgEJAQAAAA==.Elowentinsel:BAAALgAECgEJAQAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgAECgMJAwAAAA==.',
En='Enduran:BAAALgAECgYJDQAAAA==.',
Er='Erasi:BAABLgAECn8zAAMXAAkJVArnKACAAQAXAAkJVArnKACAAQAWAAUJzwLUWQBiAAAAAA==.',
Es='Es:BAABLgAECn8UAAIaAAcJ8wTGpgA0AQAaAAcJ8wTGpgA0AQAAAA==.Escanorlion:BAAALgADCgcJBwAAAA==.Esileda:BAAALgAECgQJBAAAAA==.Esttsumi:BAAALgAECgkJDwAAAA==.',
Eu='Euphia:BAAALgAECgUJDAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8pAAIJAAkJqhBuOQDJAQAJAAkJqhBuOQDJAQAAAA==.Exodiá:BAAALgADCgYJBgAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8uAAIIAAkJVB1VHgCGAgAIAAkJVB1VHgCGAgAAAA==.Faethe:BAAALgAECgEJAgABLgAECgkJPAAFAL8jAA==.Faithfulpain:BAAALgADCgYJBgAAAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farmerpolly:BAAALgADCgYJCQAAAA==.Farwolf:BAABLgAECn8oAAIJAAgJWAo7bQBaAQAJAAgJWAo7bQBaAQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECggJBwABLgAECgkJBQAEAAAAAA==.Fee:BAACLgAFFH8WAAIIAAUJYiU1EgCzAQAIAAUJYiU1EgCzAQAuAAQKfzwAAggACQmSJB8HAC0DAAgACQmSJB8HAC0DAAAA.Fellyn:BAAALgAECgQJBAAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgAECgMJAwAAAA==.Festerr:BAAALgADCgQJAQAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.Fishstick:BAAALgAECgkJDQAAAA==.',
Fl='Flameheart:BAABLgAECn8cAAMiAAgJqQoAEgAaAQAiAAgJqQoAEgAaAQAgAAEJAAIEWQEQAAAAAA==.Fleathulhu:BAACLgAFFH8JAAIWAAMJgwz2IQCXAAAWAAMJgwz2IQCXAAAuAAQKfzQAAhYACQn0HacGAP0CABYACQn0HacGAP0CAAAA.Flungpu:BAAALgADCgkJFwABLgAECgkJLwAJAKAQAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAABLgAECn8dAAMgAAYJfQwdoAD6AAAgAAYJNgwdoAD6AAAiAAEJvRLjOgA0AAAAAA==.Foxieshoxie:BAAALgAECgEJAwAAAA==.',
Fr='Frontierland:BAAALgADCgcJDQAAAA==.Frostdoom:BAAALgADCgYJCAAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgADCggJCAAAAA==.',
Fu='Furgy:BAAALgAECgEJAQAAAA==.Furrfoxsake:BAAALgAECgQJBwAAAA==.Fuzball:BAAALgADCgEJAQAAAA==.Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Galfure:BAAALgADCgYJBgAAAA==.Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAEAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn83AAIPAAkJhRYbBgACAgAPAAkJhRYbBgACAgAAAA==.',
Ge='Genovefa:BAAALgADCgYJBgAAAA==.',
Gh='Ghoulmaxing:BAAALgAECgkJBQAAAA==.Ghøulish:BAAALgAECgUJBwABLgAECggJMQANAFwMAA==.',
Gi='Gimper:BAAALgADCgcJFwAAAA==.',
Gl='Glaistia:BAAALgADCgIJAgAAAA==.Glen:BAAALgAECgUJEAAAAA==.Glowstik:BAAALgAECgQJBAAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.Gormlaîth:BAAALgAECgQJBwAAAA==.',
Gr='Grabmymelonz:BAAALgAECgUJBQAAAA==.Graeman:BAAALgADCgMJAwAAAA==.Grandpaslay:BAAALgAECgQJCQAAAA==.Greatpàw:BAAALgAECgEJAQAAAA==.Grisly:BAAALgADCgUJBQAAAA==.',
Gu='Gurrney:BAAALgADCgYJBgAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgAECgYJDgAAAA==.Habbypallie:BAAALgADCgYJFAAAAA==.Haimanist:BAABLgAECn8ZAAIOAAgJliAlAwDwAgAOAAgJliAlAwDwAgABLgAFFAcJFgABAOwZAA==.Halixan:BAABLgAECn8gAAIjAAkJWyOTAgDnAgAjAAkJWyOTAgDnAgAAAA==.Handlebardoc:BAACLgAFFH8OAAIaAAQJnxhyWQA0AQAaAAQJnxhyWQA0AQAuAAQKf0AAAhoACQleIsgQAN8CABoACQleIsgQAN8CAAAA.Harmoni:BAAALgAECgIJAgABLgAECgkJPAAFAL8jAA==.Hatorade:BAAALgAECgUJBQAAAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgAECgkJBQAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgkJEQAAAA==.',
Ho='Holyname:BAAALgAECgQJAwAAAA==.Holysim:BAAALgAECgEJAQAAAA==.',
Hu='Hunteð:BAAALgAECgEJAgAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgAECgIJAgAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8yAAMiAAkJHwyiFAD6AAAgAAkJ0AhBawBhAQAiAAYJGw6iFAD6AAAAAA==.',
Ir='Ireus:BAAALgAECgIJAgAAAA==.Ironfizt:BAAALgAECggJDwABLgAECggJJQAkAOMZAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.',
Iu='Iudex:BAAALgAECgYJBwAAAA==.Iutu:BAAALgAECgQJBAAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAABLgAECn8/AAMZAAkJNyRFAgBYAwAZAAkJNyRFAgBYAwAIAAgJRQ9LfQBoAQAAAA==.Jarvy:BAAALgAECggJCAAAAA==.',
Je='Jedavon:BAAALgAECgEJAQAAAA==.Jenhadin:BAAALgAECgUJBQAAAA==.Jerreden:BAAALgADCgYJBgAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.Jestic:BAABLgAECn8ZAAIkAAkJ5AydGQC+AQAkAAkJ5AydGQC+AQAAAA==.',
Ji='Jiangshi:BAAALgAECgQJBAAAAA==.Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ju='Justpwnedu:BAAALgAECgkJCgAAAA==.',
Ka='Kaazel:BAABLgAECn8vAAIJAAkJoBAPNwD2AQAJAAkJoBAPNwD2AQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgYJEgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgAECggJDQAAAA==.Kamsham:BAAALgADCgUJCgABLgAECgcJFwABAIIPAA==.Karea:BAAALgAECgcJDgAAAA==.Karite:BAABLgAECn80AAIlAAkJ/iJjAQDgAgAlAAkJ/iJjAQDgAgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAIRAAgJRxlqHAAhAgARAAgJRxlqHAAhAgAAAA==.Karveila:BAAALgAECgQJBAAAAA==.Katyla:BAAALgADCgQJBAABLgAECgkJMwAJAOoMAA==.Kazar:BAAALgADCgUJCQAAAA==.Kazenoth:BAABLgAECn8rAAMTAAkJxxp4FgAdAgATAAkJxxp4FgAdAgAmAAEJbxHzOQAxAAAAAA==.',
Ke='Kellement:BAAALgAECgUJBQAAAA==.Ken:BAABLgAECn8YAAIKAAgJVBZPGwDiAQAKAAgJVBZPGwDiAQABLgAECgkJPgAgADQZAA==.Kennychaoss:BAABLgAECn8sAAMCAAkJ7xxvDADrAgACAAkJ7xxvDADrAgADAAcJZw2DQwAVAQAAAA==.',
Kh='Khrisbkreme:BAAALgAECgEJAQABLgAECggJDAAEAAAAAA==.',
Ki='Kille:BAABLgAECn8XAAIJAAgJRhVZPADjAQAJAAgJRhVZPADjAQAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Kobeqt:BAAALgAECgEJAQAAAA==.Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn81AAIKAAkJ4w2bJACZAQAKAAkJ4w2bJACZAQAAAA==.Kostazu:BAABLgAECn9NAAIDAAkJKhFDJwCkAQADAAkJKhFDJwCkAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAFFAUJFgAIAGIlAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAFFAMJCQAWAIMMAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAgABLgAECgMJBgAEAAAAAA==.',
La='Laity:BAABLgAECn9GAAIIAAkJ3yDFCgAIAwAIAAkJ3yDFCgAIAwAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Laraithe:BAAALgADCgEJAQAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgAECgEJAQAAAA==.Lazraar:BAAALgAECgEJAQAAAA==.Lazylaz:BAABLgAECn8vAAIbAAkJNyT5AQAOAwAbAAkJNyT5AQAOAwABLgAFFAgJIgAaAAEeAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAABLgAECn8sAAIjAAgJ/yCUBACcAgAjAAgJ/yCUBACcAgAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJCQAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAABLgAECn8iAAMdAAYJUxhjIABiAQAdAAYJUxhjIABiAQAeAAUJhAhxwQCZAAAAAA==.Lifebloom:BAAALgAECgIJAgABLgAECgkJPwAZADckAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAFFAMJCAAfACMhAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8zAAIJAAkJ6gylTQCtAQAJAAkJ6gylTQCtAQAAAA==.Livedcargox:BAAALgAECgYJBgAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Loqir:BAAALgAFFAIJAgABLgAFFAcJHAATAE8aAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgAECgEJAQAAAA==.',
Ly='Lycanbyte:BAAALgAECgQJCwAAAA==.Lylith:BAABLgAECn82AAMdAAkJLBfnEAALAgAdAAkJLBfnEAALAgAeAAQJawU/4QBiAAAAAA==.Lyphiandraa:BAAALgAECgEJAQAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJBgAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Maddicollins:BAAALgAECgYJDAABLgAFFAIJBwAIANcbAA==.Magdalena:BAABLgAECn8yAAIJAAkJgA6GQgDOAQAJAAkJgA6GQgDOAQAAAA==.Magehawk:BAAALgAECgUJBQAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magmaface:BAAALgAECgYJBwAAAA==.Magnólia:BAABLgAECn8rAAICAAkJsyJ1CQARAwACAAkJsyJ1CQARAwAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Maithre:BAAALgAECgIJAwAAAA==.Makima:BAAALgADCgcJCQABLgAFFAQJBwAgAL8UAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Maribelle:BAAALgAECgcJCQABLgAECgkJPAAFAL8jAA==.Marrent:BAAALgADCgcJGQAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJDAAAAA==.Mazeltov:BAABLgAECn8WAAILAAgJPRrNDgAcAgALAAgJPRrNDgAcAgAAAA==.',
Me='Melomel:BAABLgAECn8eAAIjAAYJ0xEkGgAgAQAjAAYJ0xEkGgAgAQAAAA==.Melonsquezer:BAABLgAECn83AAMOAAkJsh5QBQCRAgAOAAkJsh5QBQCRAgAIAAEJ2RMVgQEwAAAAAA==.Menmei:BAABLgAECn8jAAIJAAYJFxBHggAtAQAJAAYJFxBHggAtAQAAAA==.Mexicanrage:BAAALgADCgQJBAAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgAECgUJEAAAAA==.Minien:BAABLgAECn8zAAMjAAkJcRyxCgD/AQAjAAgJ+RuxCgD/AQADAAgJeRihIQDJAQAAAA==.Minko:BAABLgAECn8rAAIJAAkJIhuBHABvAgAJAAkJIhuBHABvAgAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAFFAMJBQAFAPsKAA==.',
Mo='Modelo:BAAALgAFFAEJAQAAAA==.Molulu:BAAALgADCgcJCwABLgAECgYJFAAFABEHAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn9HAAIVAAkJuR6RAgC7AgAVAAkJuR6RAgC7AgAAAA==.Morillic:BAABLgAECn8YAAQnAAcJqxhUCgCpAQAnAAcJqxhUCgCpAQAiAAMJrA0MSACWAAAgAAIJMxSCCgFIAAABLgAECggJGgAXABgWAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgAECgEJAQAAAA==.',
Ms='Mstrcrowly:BAABLgAECn8pAAMgAAgJ/x/FFwCQAgAgAAgJ/x/FFwCQAgAnAAIJvhyGNQBAAAAAAA==.',
Mu='Mustachjones:BAABLgAECn80AAIgAAkJERxoHgBnAgAgAAkJERxoHgBnAgAAAA==.',
My='Myros:BAABLgAECn86AAMFAAkJfBYrQAAVAgAFAAkJfBYrQAAVAgAMAAEJ8gXSEwApAAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgAECgcJDAAAAA==.Narestor:BAABLgAECn8YAAIUAAgJHRPBMQDlAQAUAAgJHRPBMQDlAQABLgAECgcJFwAYAI4PAA==.Nasril:BAAALgAECgYJCgAAAA==.Nazervis:BAAALgAECgUJBQABLgAFFAgJIgAaAAEeAA==.Nazurend:BAABLgAECn8gAAIFAAgJxhK9YgCzAQAFAAgJxhK9YgCzAQAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAFFAEJAgAAAA==.Nemesîs:BAAALgADCggJEwAAAA==.Nero:BAABLgAECn8nAAIdAAkJTyF8BwCsAgAdAAkJTyF8BwCsAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMgAAgJNAUjfQBhAQAgAAgJNAUjfQBhAQAiAAIJywFjZgBDAAAAAA==.Nimuerose:BAAALgADCgMJAwAAAA==.',
No='Nortree:BAABLgAECn8gAAINAAYJ3RPySgBZAQANAAYJ3RPySgBZAQAAAA==.Nost:BAABLgAECn8sAAIIAAgJDhzBOwAKAgAIAAgJDhzBOwAKAgAAAA==.Notalock:BAAALgADCgIJAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.Novena:BAAALgAECgQJBAABLgAECgkJKwACALMiAA==.',
Nu='Nulwyrm:BAABLgAECn8rAAMTAAkJQBuUDwBmAgATAAkJQBuUDwBmAgASAAEJohisHwBKAAAAAA==.Numira:BAAALgADCgMJAwAAAA==.',
Ny='Nymue:BAAALgAECgIJAgAAAA==.Nyyrivik:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8tAAICAAgJRR/hFgCGAgACAAgJRR/hFgCGAgAAAA==.',
Oh='Ohitsadragon:BAABLgAECn8gAAISAAgJDBWeBwCzAQASAAgJDBWeBwCzAQAAAA==.',
On='Ono:BAAALgAECgEJAQAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAEAAAAAA==.Oreoscruunit:BAAALgAECgEJAgABLgAECggJDAAEAAAAAA==.',
Ow='Owl:BAABLgAECn8fAAInAAkJAwxUDQBgAQAnAAkJAwxUDQBgAQAAAA==.Owlcatraz:BAACLgAFFH8NAAINAAQJtQg/NADYAAANAAQJtQg/NADYAAAuAAQKfxUAAwoACAlXGnkYAPwBAAoACAlXGnkYAPwBAA0ABQknCyB0AM8AAAAA.',
Pa='Paendrag:BAAALgAECgUJBQAAAA==.Paladinna:BAAALgADCgMJAwAAAA==.Panadarama:BAACLgAFFH8WAAIBAAcJ7Bm5BwDxAQABAAcJ7Bm5BwDxAQAuAAQKfygAAgEACAkWJWgEAEUDAAEACAkWJWgEAEUDAAAA.Pandmei:BAAALgADCgkJCQAAAA==.Panteragon:BAABLgAECn8hAAIfAAYJPwjxNAAEAQAfAAYJPwjxNAAEAQAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAABLgAECn8bAAIJAAYJDgeYnwDzAAAJAAYJDgeYnwDzAAAAAA==.',
Pe='Peachyboy:BAAALgADCgMJAwAAAA==.Periwinkle:BAABLgAECn8eAAIWAAgJZg+QJgCDAQAWAAgJZg+QJgCDAQAAAA==.Persaud:BAACLgAFFH8PAAMgAAUJZxPiSQAlAQAgAAUJZxPiSQAlAQAnAAEJGwluJABHAAAuAAQKfxwAAyIACQkkGtsPANEBACIABwmeEtsPANEBACAABQn0HnFOAKsBAAAA.',
Ph='Phidra:BAABLgAECn9FAAMCAAkJIw+ZOAC/AQACAAkJIw+ZOAC/AQADAAQJTga/agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgAECgYJFAAFABEHAA==.Phranky:BAAALgAECgEJBAABLgAECggJDAAEAAAAAA==.Phytos:BAAALgAECgEJAQAAAA==.',
Pi='Pixiebrew:BAAALgAECgUJDgAAAA==.',
Pl='Plutrax:BAAALgAECgUJDQAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.',
Pr='Predatorc:BAABLgAECn8dAAIJAAkJaArHTgB9AQAJAAkJaArHTgB9AQAAAA==.Prepotêntê:BAAALgAECgQJBAAAAA==.Primevil:BAAALgAECgcJDQAAAA==.Primevl:BAAALgAECgcJBwAAAA==.Primévil:BAABLgAECn80AAIeAAkJ4AxPVQB7AQAeAAkJ4AxPVQB7AQAAAA==.',
Pu='Puma:BAAALgAECgYJEwAAAA==.',
Py='Pyrissa:BAAALgADCgEJAQAAAA==.',
['Pí']='Píp:BAAALgADCggJDQAAAA==.',
Qu='Quarz:BAAALgAECgMJBAAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.',
Ra='Raediant:BAAALgAECgUJBwABLgAECgkJHwABAC4VAA==.Raelek:BAAALgAECgQJBAAAAA==.Ragethecage:BAAALgADCgMJAwAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Ragsonfire:BAAALgADCgIJAgAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8lAAMUAAgJPBx/GwALAgAUAAgJPBx/GwALAgALAAcJrRTTHABCAQAAAA==.Raquel:BAABLgAECn8jAAICAAkJJQtvRwBkAQACAAkJJQtvRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAAALgAECgcJCQAAAA==.',
Re='Rede:BAAALgAECgIJAwAAAA==.Reeyou:BAAALgAECgQJBAABLgAECgkJPgAgADQZAA==.Reign:BAACLgAFFH8FAAIFAAMJ+wrYfADXAAAFAAMJ+wrYfADXAAAuAAQKf0MAAgUACQngGQ4iAJACAAUACQngGQ4iAJACAAAA.Reilu:BAAALgADCgIJAgAAAA==.Relieff:BAAALgAECgYJEwAAAA==.Relmin:BAAALgAECgEJAQAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.Revival:BAAALgAECgYJBwABLgAECgkJPwAZADckAA==.',
Ri='Rio:BAABLgAECn9BAAIdAAkJSh+OBQDZAgAdAAkJSh+OBQDZAgAAAA==.Ris:BAABLgAECn84AAIFAAkJtB/AFgDKAgAFAAkJtB/AFgDKAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgAECgMJAwAAAA==.Rockyrogue:BAAALgAECgcJDgAAAA==.Roguesgambit:BAAALgAECgkJCgAAAA==.Roknathar:BAABLgAECn8wAAMVAAkJyCWaAgC6AgAVAAgJwSWaAgC6AgAJAAMJ4R6akAARAQAAAA==.Rolldemort:BAAALgAECgIJAwAAAA==.Ronburrgandy:BAAALgAECgEJAQAAAA==.Ronilf:BAABLgAECn8lAAIkAAgJ4xkpFgDeAQAkAAgJ4xkpFgDeAQAAAA==.Rono:BAAALgADCggJEwAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8oAAMXAAkJURw8EwAvAgAXAAkJURw8EwAvAgAWAAIJyhN8iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgAECgcJCAAAAA==.Rukaza:BAAALgAECgEJAQABLgAFFAUJDAAeAJ0cAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Sabrilla:BAAALgAECgQJAwAAAA==.Saerenity:BAAALgAECgMJAwAAAA==.Sahala:BAAALgADCgEJAQAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgAECgEJAQAAAA==.Sana:BAACLgAFFH8GAAIDAAQJmRJuHgAaAQADAAQJmRJuHgAaAQAuAAQKfzAAAwMACQnYIMUHANYCAAMACQnYIMUHANYCAAIAAQlSDyHNAC4AAAAA.Saphihr:BAAALgADCgYJBgAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAEAAAAAA==.',
Se='Sedo:BAAALgAECgYJEQAAAA==.Selenis:BAAALgAECgcJDQABLgAECgkJNwAGAJolAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shamainiac:BAABLgAECn9HAAIDAAkJ8hgeEgBSAgADAAkJ8hgeEgBSAgAAAA==.Shamith:BAAALgAECgcJDgAAAA==.Shammymax:BAAALgADCgkJAQAAAA==.Shaomai:BAACLgAFFH8JAAIDAAQJyhe8HgAYAQADAAQJyhe8HgAYAQAuAAQKfysAAwMACQn1IBoKALQCAAMACQn1IBoKALQCAAIABAkvDRpzAMMAAAAA.Sharper:BAACLgAFFH8HAAIeAAQJTRWCOwAjAQAeAAQJTRWCOwAjAQAuAAQKfxcAAh4ABwlpHIRKAJoBAB4ABwlpHIRKAJoBAAEuAAUUBAkOABoAnxgA.Shep:BAAALgAECgMJAwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shi:BAAALgAECgQJBAAAAA==.Shifte:BAAALgAECgYJBgAAAA==.Shiok:BAAALgAECgMJAwAAAA==.Shishkademon:BAAALgAECgIJAgAAAA==.Shoknorris:BAAALgADCgkJCQAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgYJCwAAAA==.Silverwin:BAABLgAECn8jAAIWAAYJhhFfNwARAQAWAAYJhhFfNwARAQAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8lAAIoAAkJRRonAgA9AgAoAAkJRRonAgA9AgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJDgAAAA==.Smitted:BAABLgAECn8ZAAMIAAcJ5A7TqAAeAQAIAAcJlwvTqAAeAQAOAAYJ3QpXIwDtAAAAAA==.Smitty:BAABLgAECn8VAAMBAAgJnhU0IQCWAQABAAgJeBQ0IQCWAQApAAgJQxAfKgBdAQAAAA==.',
Sn='Snakmag:BAAALgAECgEJAQAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAAALgAECgYJEgAAAA==.Sophiaa:BAAALgADCgcJBgAAAA==.Sorn:BAABLgAECn8zAAIOAAkJRBH6DwC3AQAOAAkJRBH6DwC3AQAAAA==.',
Sp='Spaarkle:BAAALgAECgYJBwAAAA==.Specialheist:BAABLgAECn8bAAIWAAkJ1QJBRwC6AAAWAAkJ1QJBRwC6AAAAAA==.Spectrehawk:BAAALgAECgYJDAABLgAFFAQJEgAGAEsaAA==.Speçtre:BAACLgAFFH8SAAIGAAQJSxrGEQBOAQAGAAQJSxrGEQBOAQAuAAQKfy8AAwYACQkNHV0KAGICAAYACAk0IF0KAGICABoAAQn+BlJRAT0AAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgQJBAAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAABLgAECn8aAAIXAAgJGBayHwC/AQAXAAgJGBayHwC/AQAAAA==.Stormglaive:BAABLgAECn8aAAMdAAcJPxU8HQDWAQAdAAcJPxU8HQDWAQAeAAEJUwPt6QAoAAAAAA==.Strikedark:BAAALgAECgEJAQAAAA==.Stupidity:BAABLgAECn8sAAMXAAgJeB4qEgA8AgAXAAgJeB4qEgA8AgAWAAIJhBdyVAB4AAAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn9HAAMRAAkJ3x9GBwAdAwARAAkJ3x9GBwAdAwApAAgJRhTzHwCiAQAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
Sy='Synterra:BAAALgADCgkJCQAAAA==.Syranda:BAAALgAFFAEJAQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgADCgUJBQABLgAECgkJPAAFAL8jAA==.Tarysha:BAABLgAECn8qAAIkAAkJvwmdGwCsAQAkAAkJvwmdGwCsAQAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn80AAIhAAkJ5xB9HABXAQAhAAkJ5xB9HABXAQAAAA==.Tayoma:BAAALgAECgEJAgAAAA==.Tazara:BAAALgAECgQJBQAAAA==.',
Te='Tealth:BAAALgAECgYJBgAAAA==.Ted:BAABLgAECn8kAAIDAAgJghYOIwC/AQADAAgJghYOIwC/AQAAAA==.Tehgermza:BAAALgAECgcJBwAAAA==.Tehgrimza:BAABLgAECn8pAAMgAAkJ1xnbHABxAgAgAAkJ1xnbHABxAgAiAAEJrxCDdAAwAAAAAA==.Teias:BAAALgAECggJCgABLgAFFAQJEgAWANYcAA==.Teka:BAAALgADCgMJAwAAAA==.Temu:BAAALgAECgYJCAABLgAFFAQJBwAgAL8UAA==.Tet:BAABLgAFFH8GAAINAAMJAQ9oPgCvAAANAAMJAQ9oPgCvAAAAAA==.Tevia:BAABLgAECn8tAAIQAAkJ4xivDAARAgAQAAkJ4xivDAARAgAAAA==.',
Th='Thalip:BAAALgAECgQJBwAAAA==.Thekingheals:BAAALgAECgUJBQABLgAFFAMJBgApAEkZAA==.Thokmay:BAABLgAECn8pAAIpAAkJZxHxHQCwAQApAAkJZxHxHQCwAQAAAA==.Thorel:BAAALgAECgQJBAAAAA==.Thornar:BAAALgAECgUJBQAAAA==.Thunden:BAAALgAECgYJBwAAAA==.',
Ti='Tiandrinna:BAABLgAECn8qAAIMAAkJKxwSAgBCAgAMAAkJKxwSAgBCAgAAAA==.Tightywhitey:BAAALgAECgYJBwAAAA==.Timkaoss:BAABLgAECn8dAAMNAAYJtBf9UwA1AQANAAYJtBf9UwA1AQAKAAMJNQeQdwBLAAAAAA==.Timmyjudge:BAAALgAECgYJCAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAABLgAECn8jAAILAAYJIAYsMwChAAALAAYJIAYsMwChAAAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgkJFgAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgQJCAABLgAECgkJKwACALMiAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgAECgUJCwAAAA==.Trixterwolf:BAAALgADCgUJBwAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAACLgAFFH8LAAIFAAMJ7xAidgDkAAAFAAMJ7xAidgDkAAAuAAQKfy0AAgUACQlcGbk3ADMCAAUACQlcGbk3ADMCAAAA.',
Ty='Tygrassar:BAAALgAECgIJAgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8wAAIWAAkJVh0XCADeAgAWAAkJVh0XCADeAgAAAA==.',
['Tä']='Täd:BAABLgAECn8UAAIgAAYJ/RHFhQApAQAgAAYJ/RHFhQApAQAAAA==.',
Va='Vaelenka:BAAALgADCgMJAwAAAA==.Vaelune:BAAALgAECgYJBgAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAABLgAECn8iAAMHAAgJowvUEQBHAQAHAAgJCwvUEQBHAQAaAAYJPAlmxADuAAAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAACLgAFFH8GAAIIAAMJlQ9PZwDPAAAIAAMJlQ9PZwDPAAAuAAQKfyIAAggACAlXHpE4ABUCAAgACAlXHpE4ABUCAAAA.Valicous:BAAALgAECgQJCwAAAA==.Valyerian:BAABLgAECn8uAAIUAAgJ5hsOFgCcAgAUAAgJ5hsOFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgkJHgAGAGMiAA==.Vandevoker:BAAALgAECgQJCAABLgAECgkJHgAGAGMiAA==.Vanserra:BAAALgADCgcJEAAAAA==.Varregory:BAAALgADCgUJBAAAAA==.Vaxas:BAABLgAECn8jAAIIAAgJ1h8ULwA5AgAIAAgJ1h8ULwA5AgAAAA==.Vaxasus:BAAALgAECgEJAQAAAA==.Vaylorian:BAABLgAECn8VAAIhAAYJFyBZEQDEAQAhAAYJFyBZEQDEAQAAAA==.Vaült:BAABLgAECn85AAMZAAkJ8hiHDgCiAgAZAAkJ8hiHDgCiAgAIAAMJPwYbEgFzAAAAAA==.',
Ve='Velystana:BAAALgADCgIJAgAAAA==.Verianna:BAABLgAECn83AAQGAAkJmiUSAQBZAwAGAAkJFSUSAQBZAwAaAAgJZyH6LABDAgAHAAUJlhoXDgCDAQAAAA==.Vexmorphis:BAAALgAECgMJBAABLgAECgkJHgAIAJwSAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgAECgQJBAAAAA==.',
Vr='Vraknaar:BAAALgAECgMJAwAAAA==.',
Vt='Vtown:BAAALgAECgMJAwAAAA==.',
Wa='Wadumu:BAABLgAECn8xAAMNAAgJXAwOaQAYAQANAAYJVg4OaQAYAQAhAAgJlws4KwDxAAAAAA==.Wagwanmist:BAABLgAECn8tAAIRAAgJtBlQGwApAgARAAgJtBlQGwApAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warrdaddy:BAAALgAECgIJAwAAAA==.Warvegas:BAAALgAECgUJDAAAAA==.Warwulf:BAAALgAECgQJBAABLgAECggJJQAUADwcAA==.Water:BAAALgADCgEJAQAAAA==.',
Wi='Willowy:BAABLgAECn88AAIFAAkJvyM0DAASAwAFAAkJvyM0DAASAwAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8cAAQCAAUJ4hMRcgD2AAACAAUJ4hMRcgD2AAADAAQJ6whPdgB3AAAjAAEJngpXOwAxAAAAAA==.',
Xa='Xaerius:BAABLgAECn9HAAMUAAkJEBrvEABoAgAUAAkJEBrvEABoAgAQAAEJ6wWrfAAjAAAAAA==.Xalatath:BAAALgAECgUJBQAAAA==.Xan:BAABLgAECn8gAAIFAAkJyRd4TQDsAQAFAAkJyRd4TQDsAQAAAA==.Xann:BAAALgAECgIJAgAAAA==.Xannen:BAAALgADCgkJCQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAAALgAECggJEAAAAA==.Xashadin:BAAALgAECgcJBwAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIFAAcJJiNIPQCCAgAFAAcJJiNIPQCCAgAAAA==.',
Xo='Xog:BAAALgAECgIJAgAAAA==.',
Ya='Yarman:BAABLgAECn8jAAIBAAYJ4BMTMgAxAQABAAYJ4BMTMgAxAQAAAA==.',
Ye='Yeaforpie:BAABLgAECn8dAAMgAAgJ+g1bewA9AQAgAAcJEQ9bewA9AQAnAAUJAQ+QGQDgAAAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAABLgAECn8YAAIZAAgJ7BTuKQC0AQAZAAgJ7BTuKQC0AQAAAA==.',
Yo='Yoshial:BAABLgAECn8UAAIFAAYJEQer1QDjAAAFAAYJEQer1QDjAAAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAABLgAECn81AAMXAAkJThbUFgALAgAXAAkJThbUFgALAgAYAAYJPA35PQAGAQAAAA==.',
Ze='Zealins:BAAALgAECgQJBAAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQABLgAFFAUJDgAIAGkiAA==.Ziv:BAACLgAFFH8NAAINAAQJwB5OHABnAQANAAQJwB5OHABnAQAuAAQKfzUAAg0ACQkqIGkIACkDAA0ACQkqIGkIACkDAAEuAAUUAwkIAB8AIyEA.Ziyn:BAACLgAFFH8IAAIfAAMJIyEkFQAXAQAfAAMJIyEkFQAXAQAuAAQKfxgAAx8ACQk+HskGAK8CAB8ACQk+HskGAK8CAAkABgmuGjV1AEkBAAAA.',
Zo='Zoda:BAAALgAECgIJAwAAAA==.',
['Ôa']='Ôath:BAAALgAECgEJAQAAAA==.',
['Öw']='Öwlbeback:BAAALgADCgYJBgAAAA==.',
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
