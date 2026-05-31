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

local lookup = {'Monk-Brewmaster','Shaman-Restoration','Mage-Frost','Unknown-Unknown','Shaman-Elemental','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Mage-Fire','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Warrior-Arms','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Warlock-Demonology','Druid-Guardian','Priest-Shadow','Priest-Holy','Warlock-Destruction','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Evoker-Preservation','Hunter-Marksmanship','Warlock-Affliction','Mage-Arcane','Monk-Windwalker',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aarztok:BAAALgAECgUJBQABLgAFFAcJFgABAOwZAA==.',
Ac='Achepir:BAAALgADCgEJAQAAAA==.Achiella:BAAALgAECgEJAQAAAA==.',
Ad='Advisor:BAACLgAFFH8KAAICAAQJkRD3MgD1AAACAAQJkRD3MgD1AAAuAAQKfzIAAgIACQmcJG0JAOECAAIACQmcJG0JAOECAAAA.',
Ae='Aería:BAAALgAECgYJDwAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgAECgEJAQAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgADCgcJBwAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgADCgcJEAAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgAECgQJBAAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Andolas:BAAALgADCgYJCQAAAA==.Angelicuss:BAAALgAECgQJBQABLgAECgkJPAADAL8jAA==.Annya:BAAALgAECgYJBgAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aparajita:BAAALgAECgEJAQABLgABCgMJAwAEAAAAAA==.Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCwAAAA==.Aristoleh:BAAALgADCgUJBQABLgAFFAcJDQAFAIEMAA==.Arkahera:BAAALgAECgQJBQABLgAFFAcJFgABAOwZAA==.Arolder:BAABLgAECn8mAAMGAAkJqyE1BQDGAgAGAAkJdSE1BQDGAgAHAAcJZB3dAwA6AgAAAA==.Arredin:BAAALgADCgYJBgAAAA==.Arturium:BAAALgADCgYJCwAAAA==.',
As='Astayuno:BAAALgADCgQJBAAAAA==.',
At='Atabey:BAABLgAECn87AAIIAAkJICI9DQDmAgAIAAkJICI9DQDmAgABLgABCgMJAwAEAAAAAA==.Atimusk:BAAALgADCggJDwABLgAECgQJBwAEAAAAAA==.Atoadaso:BAAALgAECgQJBAAAAA==.Attretes:BAAALgADCgcJDwAAAA==.',
Az='Azazél:BAAALgADCgcJBwABLgAECgkJPQADANkXAA==.Azcowboy:BAAALgAECgMJCwAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgAECgMJAwAAAA==.',
Ba='Badco:BAAALgAECgQJBAAAAA==.Balacheck:BAABLgAECn8XAAIJAAYJyASMqADRAAAJAAYJyASMqADRAAAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgADCgQJCgAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAABLgAECn8qAAIKAAkJbxzBCgCTAgAKAAkJbxzBCgCTAgAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgYJFAAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAADAKAcAA==.',
Bi='Bigbadwoof:BAAALgADCgYJGQAAAA==.Bighog:BAABLgAFFH8TAAILAAQJ8iAfCgBmAQALAAQJ8iAfCgBmAQAAAA==.Bipbipbup:BAAALgAECgEJAQAAAA==.',
Bj='Björn:BAAALgADCgcJBwAAAA==.',
Bl='Blaazzin:BAAALgADCgcJHgAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Blinck:BAAALgADCgYJCwAAAA==.Bloomzy:BAACLgAFFH8HAAIDAAMJFiGlWAAiAQADAAMJFiGlWAAiAQAuAAQKfy4AAwMACQluGj4vAEUCAAMACQluGj4vAEUCAAwAAgl6G1oKAJ8AAAAA.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAAALgADCgYJCgAAAA==.Boombástic:BAABLgAECn8oAAMKAAkJaQ+1JwB4AQAKAAgJMhC1JwB4AQANAAIJ0A/AmwBnAAAAAA==.Boomco:BAAALgAECgcJEgAAAA==.Bors:BAAALgADCgUJEAAAAA==.Boulderholdr:BAAALgAECgQJCgAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Bravillius:BAAALgADCgcJCwAAAA==.Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAAALgAECgYJEgAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAIOAAkJyRmeCgAkAgAOAAkJyRmeCgAkAgAAAA==.Bryda:BAAALgAECgQJCgAAAA==.',
Bu='Bubblez:BAAALgADCgYJCQAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAAALgAECgQJCgAAAA==.',
Ca='Cajbo:BAABLgAECn8zAAIPAAgJQB9fAwBqAgAPAAgJQB9fAwBqAgAAAA==.Calyssa:BAABLgAECn8eAAIIAAgJ6w7jewBcAQAIAAgJ6w7jewBcAQAAAA==.Candyflöss:BAACLgAFFH8JAAILAAQJbBw7DgArAQALAAQJbBw7DgArAQAuAAQKfxkAAwsABgnTI1QNAP8BAAsABgnTI1QNAP8BABAAAQkLEDBoADMAAAAA.Capmkrunch:BAAALgAECgEJAgABLgAECgIJBAAEAAAAAA==.Caralynn:BAAALgAECgUJCQAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAABLgAECn9EAAIRAAkJGyGzBABLAwARAAkJGyGzBABLAwAAAA==.Cathelina:BAAALgADCggJDwAAAA==.Cathom:BAAALgAECgUJCgAAAA==.',
Ch='Charcasm:BAAALgAECgYJCAAAAA==.Charizaard:BAAALgAECgYJCQAAAA==.Charizaardx:BAACLgAFFH8NAAMSAAUJngpqBgDXAAASAAQJrAxqBgDXAAATAAQJQQTIMwDVAAAuAAQKf0MAAxIACQncGfIDADICABIACQn1F/IDADICABMACAnRFPYlAI0BAAAA.Chevytron:BAAALgAECgYJEwAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8bAAMUAAcJSxDDVADgAAAUAAYJYQ/DVADgAAALAAMJzgxMQABYAAAAAA==.Clives:BAAALgAECgEJAQAAAA==.Clmx:BAAALgADCgIJAgAAAA==.Clément:BAAALgADCgUJBQAAAA==.',
Co='Coffeebeans:BAABLgAECn8iAAMNAAgJExbjPgCnAQANAAcJfxTjPgCnAQAKAAgJwAv1MAA+AQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowdeath:BAAALgADCgEJAQAAAA==.Cowkiller:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgYJDgAAAA==.Crimsonthot:BAAALgAECgUJBwAAAA==.Crogan:BAAALgAECgcJEAAAAA==.Crysiscane:BAAALgADCgYJBQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQABLgAECgIJBAAEAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgADCggJCQAAAA==.Dagul:BAAALgAECgcJCwAAAA==.Dalna:BAABLgAECn8wAAIRAAgJ0xQFIgDkAQARAAgJ0xQFIgDkAQAAAA==.Danilex:BAABLgAECn8cAAIDAAgJCx9pSABeAgADAAgJCx9pSABeAgABLgAFFAgJJwAVALwZAA==.Danksoul:BAAALgAECgkJAQABLgAECggJGAAWAK4ZAA==.Darcorin:BAABLgAECn8fAAIXAAgJIBZGYwCOAQAXAAgJIBZGYwCOAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAABLgAECn8ZAAIJAAcJMQfOgwAeAQAJAAcJMQfOgwAeAQAAAA==.Darksaber:BAAALgAECgQJCgAAAA==.Dasthodan:BAAALgAECgMJBgAAAA==.Dayne:BAAALgAECgcJDQAAAA==.',
Dc='Dctrpepper:BAAALgAECgIJAgAAAA==.',
De='Deathcore:BAAALgADCgYJCgAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8uAAQNAAkJBwbLZQDxAAANAAkJBwbLZQDxAAAKAAkJWAP9QQDpAAAYAAIJhQCIOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Delvisprezly:BAAALgAECgIJBAAAAA==.Demonica:BAABLgAECn8eAAQZAAgJvwZkFADwAAAZAAgJKQZkFADwAAAaAAUJ4gYqRADmAAAbAAEJtQlTAQEtAAAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Demonspecial:BAAALgAECgkJBwAAAA==.Denastus:BAAALgADCgEJAQAAAA==.Dethknyght:BAAALgAECgkJCgABLgAFFAcJFgABAOwZAA==.Detoxin:BAAALgAECgIJAgAAAA==.Devick:BAAALgAECgEJAQAAAA==.',
Di='Dinta:BAABLgAECn9DAAIIAAkJDhu7HwByAgAIAAkJDhu7HwByAgAAAA==.Dionysys:BAAALgAECgEJAQABLgABCgMJAwAEAAAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAAALgAECgcJEgAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgAECgMJAwAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8fAAIBAAkJLhXxFAD1AQABAAkJLhXxFAD1AQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8sAAIcAAkJTg0IFwDcAQAcAAkJTg0IFwDcAQAAAA==.Dummblond:BAACLgAFFH8LAAMNAAQJFQQEOQC6AAANAAQJFQQEOQC6AAAKAAEJKwRIRgAvAAAuAAQKfx4AAw0ACAlrEXE3AKcBAA0ACAlrEXE3AKcBAAoABwkxCGxZAL4AAAAA.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAABLgAECn8XAAIdAAcJKB0wTACqAQAdAAcJKB0wTACqAQAAAA==.',
Dy='Dyonesa:BAAALgAECgUJBQAAAA==.Dysfunction:BAABLgAECn8UAAIeAAgJwRGpGQBdAQAeAAgJwRGpGQBdAQAAAA==.',
Ea='Earthshield:BAAALgAECgYJDQABLgAECgkJPwAWADckAA==.',
Eg='Ego:BAABLgAECn8fAAIWAAgJoyKpCQDcAgAWAAgJoyKpCQDcAgAAAA==.',
El='Elipto:BAAALgAECgYJBgAAAA==.Ellaana:BAAALgAECgQJDAAAAA==.Elotarra:BAAALgAECgEJAQAAAA==.Elowentinsel:BAAALgAECgEJAQAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgAECgMJAwAAAA==.',
En='Enduran:BAAALgAECgYJDQAAAA==.',
Er='Erasi:BAABLgAECn8zAAMfAAkJVAp4JwBxAQAfAAkJVAp4JwBxAQAgAAUJzwJBVgBlAAAAAA==.',
Es='Es:BAABLgAECn8UAAIXAAcJ8wTGpgA0AQAXAAcJ8wTGpgA0AQAAAA==.Escanorlion:BAAALgADCgcJBwAAAA==.Esileda:BAAALgAECgQJBAAAAA==.Esttsumi:BAAALgAECgkJDwAAAA==.',
Eu='Euphia:BAAALgAECgUJDAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8pAAIJAAkJqhBuOQDJAQAJAAkJqhBuOQDJAQAAAA==.Exodiá:BAAALgADCgYJBgAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8oAAIIAAkJ7BqGLAA2AgAIAAkJ7BqGLAA2AgAAAA==.Faethe:BAAALgAECgEJAQABLgAECgkJPAADAL8jAA==.Faithfulpain:BAAALgADCgYJBgAAAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farmerpolly:BAAALgADCgYJCQAAAA==.Farwolf:BAABLgAECn8hAAIJAAgJWAqdZgBeAQAJAAgJWAqdZgBeAQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECggJBwAAAA==.Fee:BAACLgAFFH8RAAIIAAUJ7CTVDgCzAQAIAAUJ7CTVDgCzAQAuAAQKfzsAAggACQmSJBMGAC8DAAgACQmSJBMGAC8DAAAA.Fellyn:BAAALgAECgQJBAAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgAECgIJAgAAAA==.Festerr:BAAALgADCgQJAQAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.Fishstick:BAAALgAECgQJBAAAAA==.',
Fl='Flameheart:BAABLgAECn8cAAMhAAgJqQraEAAcAQAhAAgJqQraEAAcAQAdAAEJAAI+TAERAAAAAA==.Fleathulhu:BAACLgAFFH8GAAIgAAIJ3wr2JgBlAAAgAAIJ3wr2JgBlAAAuAAQKfzMAAiAACQmsHI0HAOICACAACQmsHI0HAOICAAAA.Flungpu:BAAALgADCgkJFwABLgAECggJKQAJAHsMAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAABLgAECn8dAAMdAAYJfQywmQAAAQAdAAYJNgywmQAAAQAhAAEJvRLiNwA1AAAAAA==.Foxieshoxie:BAAALgAECgEJAwAAAA==.',
Fr='Frontierland:BAAALgADCgcJDQAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgADCggJCAAAAA==.',
Fu='Furgy:BAAALgAECgEJAQAAAA==.Furrfoxsake:BAAALgAECgQJBgAAAA==.Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Galfure:BAAALgADCgYJBgAAAA==.Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAEAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn83AAIPAAkJhRaZBQAKAgAPAAkJhRaZBQAKAgAAAA==.',
Ge='Genovefa:BAAALgADCgYJBgAAAA==.',
Gh='Ghoulmaxing:BAAALgAECgYJBQABLgAECggJBwAEAAAAAA==.Ghøulish:BAAALgAECgUJBwABLgAECggJMQANAFwMAA==.',
Gi='Gimper:BAAALgADCgcJFwAAAA==.',
Gl='Glaistia:BAAALgADCgIJAgAAAA==.Glen:BAAALgAECgQJDAAAAA==.Glowstik:BAAALgAECgQJBAAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.Gormlaîth:BAAALgAECgQJBwAAAA==.',
Gr='Grabmymelonz:BAAALgAECgUJBQAAAA==.Graeman:BAAALgADCgMJAwAAAA==.Grandpaslay:BAAALgAECgQJCQAAAA==.Greatpàw:BAAALgAECgEJAQAAAA==.Grisly:BAAALgADCgUJBQAAAA==.',
Gu='Gurrney:BAAALgADCgYJBgAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgAECgUJCgAAAA==.Habbypallie:BAAALgADCgYJFAAAAA==.Haimanist:BAABLgAECn8ZAAIOAAgJliAlAwDwAgAOAAgJliAlAwDwAgABLgAFFAcJFgABAOwZAA==.Halixan:BAABLgAECn8fAAIiAAgJFiNPBQB7AgAiAAgJFiNPBQB7AgAAAA==.Handlebardoc:BAACLgAFFH8OAAIXAAQJnxhlTAA6AQAXAAQJnxhlTAA6AQAuAAQKf0AAAhcACQleIiMPAOICABcACQleIiMPAOICAAAA.Harmoni:BAAALgAECgIJAgABLgAECgkJPAADAL8jAA==.Hatorade:BAAALgAECgUJBQAAAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgAECgkJBQAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgYJEAAAAA==.',
Ho='Holyname:BAAALgAECgQJAwAAAA==.Holysim:BAAALgAECgEJAQAAAA==.',
Hu='Hunteð:BAAALgAECgEJAgAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgAECgIJAgAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8yAAMhAAkJHwxSEwD8AAAdAAkJ0Ag2ZgBnAQAhAAYJGw5SEwD8AAAAAA==.',
Ir='Ireus:BAAALgAECgIJAgAAAA==.Ironfizt:BAAALgAECggJDwABLgAECggJJQAjAOMZAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.',
Iu='Iudex:BAAALgAECgYJBwAAAA==.Iutu:BAAALgAECgQJBAAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAABLgAECn8/AAMWAAkJNyRFAgBYAwAWAAkJNyRFAgBYAwAIAAgJRQ9ZeQBhAQAAAA==.Jarvy:BAAALgAECggJCAAAAA==.',
Je='Jedavon:BAAALgAECgEJAQAAAA==.Jerreden:BAAALgADCgYJBgAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.Jestic:BAAALgAECgcJDgAAAA==.',
Ji='Jiangshi:BAAALgAECgQJBAAAAA==.Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ju='Justpwnedu:BAAALgAECgkJCgAAAA==.',
Ka='Kaazel:BAABLgAECn8pAAIJAAgJewxuWwB6AQAJAAgJewxuWwB6AQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgYJEgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgAECggJDQAAAA==.Kamsham:BAAALgADCgUJBQABLgAECgcJFgABAIIPAA==.Karea:BAAALgAECgcJBwAAAA==.Karite:BAABLgAECn80AAIkAAkJ/iI+AQDhAgAkAAkJ/iI+AQDhAgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAIRAAgJRxkxGgAgAgARAAgJRxkxGgAgAgAAAA==.Karveila:BAAALgAECgQJBAAAAA==.Katyla:BAAALgADCgQJBAABLgAECgkJMwAJAOoMAA==.Kazar:BAAALgADCgUJCQAAAA==.Kazenoth:BAABLgAECn8rAAMTAAkJxxoRFQAZAgATAAkJxxoRFQAZAgAlAAEJbxHINwAxAAAAAA==.',
Ke='Kellement:BAAALgAECgUJBQAAAA==.Ken:BAAALgAECggJEgAAAA==.Kennychaoss:BAABLgAECn8kAAMCAAkJzBj9EwCSAgACAAkJzBj9EwCSAgAFAAcJZw26PwAZAQAAAA==.',
Kh='Khrisbkreme:BAAALgAECgEJAQABLgAECgIJBAAEAAAAAA==.',
Ki='Kille:BAAALgAECgcJEwAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Kobeqt:BAAALgAECgEJAQAAAA==.Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn8uAAIKAAgJRA5aLABZAQAKAAgJRA5aLABZAQAAAA==.Kostazu:BAABLgAECn9FAAIFAAkJNRB4KQCKAQAFAAkJNRB4KQCKAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAFFAUJEQAIAOwkAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAFFAIJBgAgAN8KAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAgABLgAECgMJBgAEAAAAAA==.',
La='Laity:BAABLgAECn8+AAIIAAkJrh8RDwDXAgAIAAkJrh8RDwDXAgAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Laraithe:BAAALgADCgEJAQAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgAECgEJAQAAAA==.Lazraar:BAAALgAECgEJAQAAAA==.Lazylaz:BAABLgAECn8vAAIYAAkJNySsAQARAwAYAAkJNySsAQARAwABLgAFFAgJIgAXAAEeAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAABLgAECn8lAAIiAAgJ/yBUBACZAgAiAAgJ/yBUBACZAgAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJCQAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAABLgAECn8iAAMaAAYJUxgSHgBlAQAaAAYJUxgSHgBlAQAbAAUJhAh2vACOAAAAAA==.Lifebloom:BAAALgAECgIJAgABLgAECgkJPwAWADckAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAFFAMJCAAcACMhAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8zAAIJAAkJ6gwTSACxAQAJAAkJ6gwTSACxAQAAAA==.Livedcargox:BAAALgAECgYJBgAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgAECgEJAQAAAA==.',
Ly='Lycanbyte:BAAALgAECgQJBwAAAA==.Lylith:BAABLgAECn82AAMaAAkJLBd6DwAOAgAaAAkJLBd6DwAOAgAbAAQJawWA3gBVAAAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJBQAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Maddicollins:BAAALgAECgYJBgABLgAFFAIJBwAIANcbAA==.Magdalena:BAABLgAECn8pAAIJAAgJPw86UgCTAQAJAAgJPw86UgCTAQAAAA==.Magehawk:BAAALgAECgUJBQAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magmaface:BAAALgAECgYJBwAAAA==.Magnólia:BAABLgAECn8nAAICAAgJGiSWDgDHAgACAAgJGiSWDgDHAgAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Maithre:BAAALgAECgIJAwAAAA==.Makima:BAAALgADCgcJCQABLgAFFAMJAwAEAAAAAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Maribelle:BAAALgAECgMJAwABLgAECgkJPAADAL8jAA==.Marrent:BAAALgADCgcJGQAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJDAAAAA==.Mazeltov:BAABLgAECn8WAAILAAgJPRrNDgAcAgALAAgJPRrNDgAcAgAAAA==.',
Me='Melomel:BAABLgAECn8eAAIiAAYJ0xEzGAAhAQAiAAYJ0xEzGAAhAQAAAA==.Melonsquezer:BAABLgAECn83AAMOAAkJsh7WBACVAgAOAAkJsh7WBACVAgAIAAEJ2RPeMwE9AAAAAA==.Menmei:BAABLgAECn8jAAIJAAYJFxDneQAyAQAJAAYJFxDneQAyAQAAAA==.Mexicanrage:BAAALgADCgQJBAAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgAECgUJCwAAAA==.Minien:BAABLgAECn8yAAMFAAgJHB1eHwDOAQAFAAgJeRheHwDOAQAiAAcJrRzpDQC0AQAAAA==.Minko:BAABLgAECn8rAAIJAAkJIhvGGQB1AgAJAAkJIhvGGQB1AgAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAECgkJPQADANkXAA==.',
Mo='Modelo:BAAALgAFFAEJAQAAAA==.Molulu:BAAALgADCgcJCwABLgAECgUJDgAEAAAAAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn9FAAImAAkJ+B10AgC6AgAmAAkJ+B10AgC6AgAAAA==.Morillic:BAABLgAECn8YAAQnAAcJqxhXCQCtAQAnAAcJqxhXCQCtAQAhAAMJrA0MSACWAAAdAAIJMxSCCgFIAAABLgAECggJGgAfABgWAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgAECgEJAQAAAA==.',
Ms='Mstrcrowly:BAABLgAECn8jAAMdAAgJbR+aGACEAgAdAAgJbR+aGACEAgAnAAIJvhzaMQBAAAAAAA==.',
Mu='Mustachjones:BAABLgAECn80AAIdAAkJERxDHABtAgAdAAkJERxDHABtAgAAAA==.',
My='Myros:BAABLgAECn86AAMDAAkJfBZePAASAgADAAkJfBZePAASAgAMAAEJ8gXzEQArAAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgAECgUJBQAAAA==.Narestor:BAABLgAECn8YAAIUAAgJHRPBMQDlAQAUAAgJHRPBMQDlAQABLgAECgcJFwAVAI4PAA==.Nasril:BAAALgAECgQJBAAAAA==.Nazervis:BAAALgAECgUJBQABLgAFFAgJIgAXAAEeAA==.Nazurend:BAABLgAECn8cAAIDAAgJuREgaACTAQADAAgJuREgaACTAQAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAFFAEJAQAAAA==.Nemesîs:BAAALgADCggJDQAAAA==.Nero:BAABLgAECn8nAAIaAAkJTyGRBgCzAgAaAAkJTyGRBgCzAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMdAAgJNAUjfQBhAQAdAAgJNAUjfQBhAQAhAAIJywFjZgBDAAAAAA==.Nimuerose:BAAALgADCgMJAwAAAA==.',
No='Nortree:BAABLgAECn8gAAINAAYJ3ROySABZAQANAAYJ3ROySABZAQAAAA==.Nost:BAABLgAECn8sAAIIAAgJDhxcNwALAgAIAAgJDhxcNwALAgAAAA==.Notalock:BAAALgADCgIJAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.Novena:BAAALgAECgMJAwABLgAECggJJwACABokAA==.',
Nu='Nulwyrm:BAABLgAECn8mAAITAAgJphvpFQASAgATAAgJphvpFQASAgAAAA==.Numira:BAAALgADCgMJAwAAAA==.',
Ny='Nyyrivik:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8tAAICAAgJRR/3FACJAgACAAgJRR/3FACJAgAAAA==.',
Oh='Ohitsadragon:BAABLgAECn8fAAISAAcJSBfVCACMAQASAAcJSBfVCACMAQAAAA==.',
On='Ono:BAAALgAECgEJAQAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAEAAAAAA==.Oreoscruunit:BAAALgAECgEJAgABLgAECgIJBAAEAAAAAA==.',
Ow='Owl:BAABLgAECn8fAAInAAkJAwxUDQBgAQAnAAkJAwxUDQBgAQAAAA==.Owlcatraz:BAACLgAFFH8NAAINAAQJtQhFLwDlAAANAAQJtQhFLwDlAAAuAAQKfxUAAwoACAlXGjMXAP0BAAoACAlXGjMXAP0BAA0ABQknCzRxAM8AAAAA.',
Pa='Paendrag:BAAALgAECgUJBQAAAA==.Panadarama:BAACLgAFFH8WAAIBAAcJ7BkHBgD7AQABAAcJ7BkHBgD7AQAuAAQKfygAAgEACAkWJWgEAEUDAAEACAkWJWgEAEUDAAAA.Pandmei:BAAALgADCgkJCQAAAA==.Panteragon:BAABLgAECn8hAAIcAAYJPwjGMgAFAQAcAAYJPwjGMgAFAQAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAABLgAECn8bAAIJAAYJDge2lgD3AAAJAAYJDge2lgD3AAAAAA==.',
Pe='Peachyboy:BAAALgADCgMJAwAAAA==.Periwinkle:BAABLgAECn8eAAIgAAgJZg8jJACMAQAgAAgJZg8jJACMAQAAAA==.Persaud:BAACLgAFFH8KAAIdAAQJ6RKmQgAuAQAdAAQJ6RKmQgAuAQAuAAQKfxwAAyEACQkkGtsPANEBACEABwmeEtsPANEBAB0ABQn0HlNLAK0BAAAA.',
Ph='Phidra:BAABLgAECn8+AAMCAAkJUA18PQCcAQACAAkJUA18PQCcAQAFAAQJTga/agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgAECgUJDgAEAAAAAA==.Phranky:BAAALgAECgEJAwABLgAECgIJBAAEAAAAAA==.Phytos:BAAALgAECgEJAQAAAA==.',
Pi='Pixiebrew:BAAALgAECgUJDgAAAA==.',
Pl='Plutrax:BAAALgAECgQJCAAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.',
Pr='Predatorc:BAABLgAECn8dAAIJAAkJaArHTgB9AQAJAAkJaArHTgB9AQAAAA==.Primevil:BAAALgAECgcJDQAAAA==.Primevl:BAAALgADCgQJBAAAAA==.Primévil:BAABLgAECn8zAAIbAAkJ2QwOUgB4AQAbAAkJ2QwOUgB4AQAAAA==.',
Pu='Puma:BAAALgAECgYJEwAAAA==.',
['Pí']='Píp:BAAALgADCggJDQAAAA==.',
Qu='Quarz:BAAALgAECgIJAwAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.',
Ra='Raediant:BAAALgAECgUJBwABLgAECgkJHwABAC4VAA==.Raelek:BAAALgAECgQJBAAAAA==.Ragethecage:BAAALgADCgMJAwAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8lAAMUAAgJPBxsGQAOAgAUAAgJPBxsGQAOAgALAAcJrRQjGwBHAQAAAA==.Raquel:BAABLgAECn8jAAICAAkJJQtvRwBkAQACAAkJJQtvRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAAALgAECgMJAwAAAA==.',
Re='Rede:BAAALgAECgIJAwAAAA==.Reeyou:BAAALgADCgMJAwABLgAECggJEgAEAAAAAA==.Reign:BAABLgAECn89AAIDAAkJ2RdwJwBnAgADAAkJ2RdwJwBnAgABLgAECgkJPQADANkXAA==.Reilu:BAAALgADCgIJAgAAAA==.Relieff:BAAALgAECgYJEwAAAA==.Relmin:BAAALgAECgEJAQAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.Revival:BAAALgAECgIJAgABLgAECgkJPwAWADckAA==.',
Ri='Rio:BAABLgAECn85AAIaAAkJex2IBgCzAgAaAAkJex2IBgCzAgAAAA==.Ris:BAABLgAECn8xAAIDAAkJtB8IGQCtAgADAAkJtB8IGQCtAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgAECgMJAwAAAA==.Rockyrogue:BAAALgAECgcJBwAAAA==.Roguesgambit:BAAALgAECgkJCgAAAA==.Roknathar:BAABLgAECn8wAAMmAAkJyCVaAgDAAgAmAAgJwSVaAgDAAgAJAAMJ4R7PiAAUAQAAAA==.Ronburrgandy:BAAALgAECgEJAQAAAA==.Ronilf:BAABLgAECn8lAAIjAAgJ4xmWFADkAQAjAAgJ4xmWFADkAQAAAA==.Rono:BAAALgADCggJEwAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8oAAMfAAkJURy8EQArAgAfAAkJURy8EQArAgAgAAIJyhN8iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgAECgcJBwAAAA==.Rukaza:BAAALgAECgEJAQABLgAFFAUJDAAbAJ0cAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Sabrilla:BAAALgAECgQJAwAAAA==.Saerenity:BAAALgAECgMJAwAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgAECgEJAQAAAA==.Sana:BAABLgAECn8wAAMFAAkJ2CAABwDbAgAFAAkJ2CAABwDbAgACAAEJUg84wgAuAAAAAA==.Saphihr:BAAALgADCgYJBgAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAEAAAAAA==.',
Se='Sedo:BAAALgAECgYJDQAAAA==.Selenis:BAAALgAECgcJDQABLgAECgkJMAAXANskAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shamainiac:BAABLgAECn9FAAIFAAkJdxhAEQBRAgAFAAkJdxhAEQBRAgAAAA==.Shamith:BAAALgAECgYJBwAAAA==.Shaomai:BAACLgAFFH8GAAIFAAMJUhfsKADSAAAFAAMJUhfsKADSAAAuAAQKfysAAwUACQn1ICYJALgCAAUACQn1ICYJALgCAAIABAkvDRpzAMMAAAEuAAUUBAkIAA4AIw4A.Sharper:BAABLgAECn8XAAIbAAcJaRx8RwCYAQAbAAcJaRx8RwCYAQABLgAFFAQJDgAXAJ8YAA==.Shep:BAAALgAECgMJAwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shiok:BAAALgAECgMJAwAAAA==.Shishkademon:BAAALgAECgIJAgAAAA==.Shoknorris:BAAALgADCgkJCQAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgUJCgAAAA==.Silverwin:BAABLgAECn8jAAIgAAYJhhFINQAWAQAgAAYJhhFINQAWAQAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8lAAIoAAkJRRrxAQBIAgAoAAkJRRrxAQBIAgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJDgAAAA==.Smitted:BAABLgAECn8ZAAMIAAcJ5A6MogAYAQAIAAcJlwuMogAYAQAOAAYJ3QpXIwDtAAAAAA==.Smitty:BAABLgAECn8VAAMBAAgJnhWfHwCYAQABAAgJeBSfHwCYAQApAAgJQxDsJgBnAQAAAA==.',
Sn='Snakmag:BAAALgAECgEJAQAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAAALgAECgYJEgAAAA==.Sophiaa:BAAALgADCgcJBgAAAA==.Sorn:BAABLgAECn8qAAIOAAgJShI/EwB8AQAOAAgJShI/EwB8AQAAAA==.',
Sp='Spaarkle:BAAALgAECgYJBwAAAA==.Specialheist:BAABLgAECn8bAAIgAAkJ1QLpQwDDAAAgAAkJ1QLpQwDDAAAAAA==.Spectrehawk:BAAALgAECgYJDAABLgAFFAQJEgAGAEsaAA==.Speçtre:BAACLgAFFH8SAAIGAAQJSxriDgBVAQAGAAQJSxriDgBVAQAuAAQKfy8AAwYACQkNHXgJAGYCAAYACAk0IHgJAGYCABcAAQn+Bh1AAT0AAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgQJBAAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAABLgAECn8aAAIfAAgJGBadHQC5AQAfAAgJGBadHQC5AQAAAA==.Stormglaive:BAABLgAECn8aAAMaAAcJPxU8HQDWAQAaAAcJPxU8HQDWAQAbAAEJUwPt6QAoAAAAAA==.Strikedark:BAAALgAECgEJAQAAAA==.Stupidity:BAABLgAECn8sAAMfAAgJeB7AEAA2AgAfAAgJeB7AEAA2AgAgAAIJhBeoUQB6AAAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn9AAAMRAAkJ3x+JBgAdAwARAAkJ3x+JBgAdAwApAAYJWBPxKQBSAQAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
Sy='Syranda:BAAALgAFFAEJAQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgADCgUJBQABLgAECgkJPAADAL8jAA==.Tarysha:BAABLgAECn8hAAIjAAgJ6wmDIQBvAQAjAAgJ6wmDIQBvAQAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn80AAIeAAkJ5xClGQBdAQAeAAkJ5xClGQBdAQAAAA==.Tayoma:BAAALgAECgEJAQAAAA==.Tazara:BAAALgAECgQJBQAAAA==.',
Te='Tealth:BAAALgAECgYJBgAAAA==.Ted:BAABLgAECn8jAAIFAAcJTxcAKQCOAQAFAAcJTxcAKQCOAQAAAA==.Tehgermza:BAAALgAECgcJBwAAAA==.Tehgrimza:BAABLgAECn8nAAMdAAkJVRkLHQBoAgAdAAkJVRkLHQBoAgAhAAEJrxCDdAAwAAAAAA==.Teias:BAAALgAECggJCgABLgAFFAQJDgAgACIaAA==.Teka:BAAALgADCgMJAwAAAA==.Temu:BAAALgAECgYJCAABLgAFFAMJAwAEAAAAAA==.Tet:BAABLgAFFH8FAAINAAMJ0g0dOgC2AAANAAMJ0g0dOgC2AAAAAA==.Tevia:BAABLgAECn8tAAIQAAkJ4xiqCwAUAgAQAAkJ4xiqCwAUAgAAAA==.',
Th='Thalip:BAAALgAECgQJBwAAAA==.Thekingheals:BAAALgAECgIJAgABLgAECggJJgApAAsfAA==.Thokmay:BAABLgAECn8mAAIpAAkJyA+UIwB+AQApAAkJyA+UIwB+AQAAAA==.Thorel:BAAALgAECgQJBAAAAA==.Thornar:BAAALgAECgUJBQAAAA==.Thunden:BAAALgAECgYJBgAAAA==.',
Ti='Tiandrinna:BAABLgAECn8qAAIMAAkJKxy4AQBYAgAMAAkJKxy4AQBYAgAAAA==.Tightywhitey:BAAALgAECgYJBwAAAA==.Timkaoss:BAABLgAECn8dAAMNAAYJtBeLUQA2AQANAAYJtBeLUQA2AQAKAAMJNQfecQBLAAAAAA==.Timmyjudge:BAAALgAECgYJCAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAABLgAECn8jAAILAAYJIAa2MACkAAALAAYJIAa2MACkAAAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgkJFgAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgMJBwABLgAECggJJwACABokAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgAECgMJBgAAAA==.Trixterwolf:BAAALgADCgUJBwAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAACLgAFFH8HAAIDAAMJggefegDLAAADAAMJggefegDLAAAuAAQKfy0AAgMACQlcGR01ACwCAAMACQlcGR01ACwCAAAA.',
Ty='Tygrassar:BAAALgAECgIJAgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8wAAIgAAkJVh07BwDoAgAgAAkJVh07BwDoAgAAAA==.',
['Tä']='Täd:BAAALgAFFAEJAQAAAA==.',
Va='Vaelenka:BAAALgADCgMJAwAAAA==.Vaelune:BAAALgAECgYJBgAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAABLgAECn8fAAMHAAgJxgrgEQAoAQAHAAgJLgrgEQAoAQAXAAYJPAm+ugDuAAAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAACLgAFFH8GAAIIAAMJlQ8OWwDYAAAIAAMJlQ8OWwDYAAAuAAQKfyIAAggACAlXHuYzABgCAAgACAlXHuYzABgCAAAA.Valicous:BAAALgAECgQJBwAAAA==.Valyerian:BAABLgAECn8uAAIUAAgJ5hsOFgCcAgAUAAgJ5hsOFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgkJHgAGAGMiAA==.Vandevoker:BAAALgAECgQJCAABLgAECgkJHgAGAGMiAA==.Vanserra:BAAALgADCgcJEAAAAA==.Varregory:BAAALgADCgUJBAAAAA==.Vaxas:BAABLgAECn8jAAIIAAgJ1h9EKwA7AgAIAAgJ1h9EKwA7AgAAAA==.Vaxasus:BAAALgAECgEJAQAAAA==.Vaylorian:BAABLgAECn8VAAIeAAYJFyDyDwDHAQAeAAYJFyDyDwDHAQAAAA==.Vaült:BAABLgAECn8yAAMWAAkJOBYkGAAwAgAWAAkJOBYkGAAwAgAIAAMJPwYbEgFzAAAAAA==.',
Ve='Velystana:BAAALgADCgIJAgAAAA==.Verianna:BAABLgAECn8wAAQXAAkJ2ySvKQBGAgAXAAgJZyGvKQBGAgAGAAUJCiVZDgAJAgAHAAUJlhpvDACBAQAAAA==.Vexmorphis:BAAALgAECgIJAgABLgAECgkJHgAIAJwSAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgAECgQJBAAAAA==.',
Vr='Vraknaar:BAAALgADCgQJBAAAAA==.',
Vt='Vtown:BAAALgAECgMJAwAAAA==.',
Wa='Wadumu:BAABLgAECn8xAAMNAAgJXAwOaQAYAQANAAYJVg4OaQAYAQAeAAgJlwtfJwD0AAAAAA==.Wagwanmist:BAABLgAECn8tAAIRAAgJtBkPGQAqAgARAAgJtBkPGQAqAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warrdaddy:BAAALgAECgEJAgAAAA==.Warvegas:BAAALgAECgQJCAAAAA==.Warwulf:BAAALgAECgQJBAABLgAECggJJQAUADwcAA==.Water:BAAALgADCgEJAQAAAA==.',
Wi='Willowy:BAABLgAECn88AAIDAAkJvyPUCgAPAwADAAkJvyPUCgAPAwAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8cAAQCAAUJ4hNXbAD3AAACAAUJ4hNXbAD3AAAFAAQJ6wggbwB8AAAiAAEJngo/NgAxAAAAAA==.',
Xa='Xaerius:BAABLgAECn9AAAMUAAkJyxlcEABjAgAUAAkJyxlcEABjAgAQAAEJ6wXDdAAjAAAAAA==.Xalatath:BAAALgADCgcJDQAAAA==.Xan:BAABLgAECn8gAAIDAAkJyRdjSQDoAQADAAkJyRdjSQDoAQAAAA==.Xann:BAAALgAECgIJAgAAAA==.Xannen:BAAALgADCgkJCQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAAALgAECggJEAAAAA==.Xashadin:BAAALgAECgcJBwAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIDAAcJJiNIPQCCAgADAAcJJiNIPQCCAgAAAA==.',
Xo='Xog:BAAALgAECgIJAgAAAA==.',
Ya='Yarman:BAABLgAECn8jAAIBAAYJ4BPsLwAyAQABAAYJ4BPsLwAyAQAAAA==.',
Ye='Yeaforpie:BAABLgAECn8cAAMdAAgJyQ3ddQBDAQAdAAcJEQ/ddQBDAQAnAAQJwgszIACXAAAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAABLgAECn8YAAIWAAgJ7BT5JwC1AQAWAAgJ7BT5JwC1AQAAAA==.',
Yo='Yoshial:BAAALgAECgUJDgAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAABLgAECn81AAMfAAkJThYSFgD+AQAfAAkJThYSFgD+AQAVAAYJPA1MOQAEAQAAAA==.',
Ze='Zealins:BAAALgADCgUJCAAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQABLgAFFAUJDgAIAGkiAA==.Ziv:BAACLgAFFH8JAAINAAQJMx1qGwBeAQANAAQJMx1qGwBeAQAuAAQKfzUAAg0ACQkqIOcHACsDAA0ACQkqIOcHACsDAAEuAAUUAwkIABwAIyEA.Ziyn:BAACLgAFFH8IAAIcAAMJIyHrEwAgAQAcAAMJIyHrEwAgAQAuAAQKfxgAAxwACQk+HiwGALQCABwACQk+HiwGALQCAAkABgmuGmduAEwBAAAA.',
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
