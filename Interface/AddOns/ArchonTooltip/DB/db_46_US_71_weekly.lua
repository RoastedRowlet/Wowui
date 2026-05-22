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

local lookup = {'Monk-Brewmaster','Shaman-Restoration','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Mage-Fire','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Priest-Discipline','DeathKnight-Unholy','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Warlock-Demonology','Paladin-Holy','Priest-Shadow','Priest-Holy','Warlock-Destruction','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Evoker-Preservation','Shaman-Elemental','Hunter-Marksmanship','Warlock-Affliction','Mage-Arcane','Monk-Windwalker','Druid-Guardian','Warrior-Arms',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aarztok:BAAALgAECgUJBQABLgAFFAUJDwABAIcdAA==.',
Ac='Achiella:BAAALgADCgIJAgAAAA==.',
Ad='Advisor:BAACLgAFFH8KAAICAAQJkRDlIQAEAQACAAQJkRDlIQAEAQAuAAQKfygAAgIACQktJG0JAOECAAIACQktJG0JAOECAAAA.',
Ae='Aería:BAAALgAECgYJDwAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgAECgEJAQAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgADCgcJBwAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgADCgcJEAAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgADCgkJHAAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Andolas:BAAALgADCgMJAwAAAA==.Angelicuss:BAAALgAECgQJBAABLgAECggJLAADACMkAA==.Annya:BAAALgAECgYJBgAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCwAAAA==.Arkahera:BAAALgAECgQJBQABLgAFFAUJDwABAIcdAA==.Arolder:BAABLgAECn8gAAMEAAkJNiDyBACiAgAEAAkJiB/yBACiAgAFAAcJZB3dAwA6AgAAAA==.Arturium:BAAALgADCgYJCQAAAA==.',
As='Astayuno:BAAALgADCgQJBAAAAA==.',
At='Atabey:BAABLgAECn87AAIGAAkJICI0BwACAwAGAAkJICI0BwACAwABLgABCgMJAwAHAAAAAA==.Atimusk:BAAALgADCggJDwAAAA==.Atoadaso:BAAALgAECgQJBAAAAA==.Attretes:BAAALgADCgcJDwAAAA==.',
Az='Azcowboy:BAAALgAECgMJCwAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgAECgMJAwAAAA==.',
Ba='Balacheck:BAABLgAECn8XAAIIAAYJyAQQhADTAAAIAAYJyAQQhADTAAAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgADCgQJCgAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAABLgAECn8hAAIJAAgJoxr6EgDqAQAJAAgJoxr6EgDqAQAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgQJDgAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAADAKAcAA==.',
Bi='Bigbadwoof:BAAALgADCgYJGQAAAA==.Bighog:BAABLgAFFH8QAAIKAAQJsB4SBwBgAQAKAAQJsB4SBwBgAQAAAA==.Bipbipbup:BAAALgADCgQJBAAAAA==.',
Bl='Blaazzin:BAAALgADCgcJGAAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Bloomzy:BAABLgAECn8sAAMDAAkJohZGLQAiAgADAAkJohZGLQAiAgALAAIJehtaCgCfAAAAAA==.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAAALgADCgYJCgAAAA==.Boombástic:BAABLgAECn8mAAMJAAkJYg+OHgB4AQAJAAgJKhCOHgB4AQAMAAIJ0A8BhgBnAAAAAA==.Boomco:BAAALgAECgUJBwAAAA==.Bors:BAAALgADCgQJCwAAAA==.Boulderholdr:BAAALgAECgMJAwAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAAALgAECgYJEgAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAINAAkJyRmeCgAkAgANAAkJyRmeCgAkAgAAAA==.Bryda:BAAALgAECgMJAwAAAA==.',
Bu='Bubblez:BAAALgADCgYJCQAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAAALgAECgMJAwAAAA==.',
Ca='Cajbo:BAABLgAECn8oAAIOAAgJGR7uAgBQAgAOAAgJGR7uAgBQAgAAAA==.Calyssa:BAABLgAECn8dAAIGAAcJ7Q2tfQAnAQAGAAcJ7Q2tfQAnAQAAAA==.Candyflöss:BAABLgAFFH8FAAIKAAMJvBzDDgDzAAAKAAMJvBzDDgDzAAAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAABLgAECn87AAIPAAkJDB8pBQADAwAPAAkJDB8pBQADAwAAAA==.Cathelina:BAAALgADCggJDwAAAA==.Cathom:BAAALgAECgQJCQAAAA==.',
Ch='Charizaard:BAAALgAECgUJBQAAAA==.Charizaardx:BAACLgAFFH8KAAMQAAQJIQUKBQDMAAARAAQJQQQWJQDyAAAQAAMJWwUKBQDMAAAuAAQKfzwAAxAACQmSFwYGAK4BABAACAmuFAYGAK4BABEACAnSFPYlAI0BAAAA.Chevytron:BAAALgAECgYJEwAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8ZAAMSAAcJSxCQQgDnAAASAAYJYQ+QQgDnAAAKAAMJzgxfNABeAAAAAA==.Clément:BAAALgADCgUJBQAAAA==.',
Co='Coffeebeans:BAABLgAECn8iAAMMAAgJExbjPgCnAQAMAAcJfxTjPgCnAQAJAAgJwQuZJgA8AQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowkiller:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgYJCgAAAA==.Crimsonthot:BAAALgADCgEJAQAAAA==.Crogan:BAAALgAECgcJEAAAAA==.Crysiscane:BAAALgADCgYJBQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQABLgAECgIJBAAHAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgADCggJCQAAAA==.Dalna:BAABLgAECn8lAAIPAAgJ9g4VJgBrAQAPAAgJ9g4VJgBrAQAAAA==.Danilex:BAABLgAECn8cAAIDAAgJCx9pSABeAgADAAgJCx9pSABeAgABLgAFFAcJIAATAL4XAA==.Danksoul:BAAALgADCgUJBQABLgAECgUJBQAHAAAAAA==.Darcorin:BAABLgAECn8fAAIUAAgJIBbJTACUAQAUAAgJIBbJTACUAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAAALgAECgUJEgAAAA==.Darksaber:BAAALgAECgMJAwAAAA==.Dasthodan:BAAALgAECgMJAwAAAA==.Dayne:BAAALgAECgUJBgAAAA==.',
Dc='Dctrpepper:BAAALgAECgIJAgAAAA==.',
De='Deathcore:BAAALgADCgUJBQAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8pAAQMAAkJ9AabXADcAAAMAAgJWwabXADcAAAJAAkJzgLwOQDRAAAVAAIJhQCIOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Delvisprezly:BAAALgAECgIJBAAAAA==.Demonica:BAABLgAECn8VAAQWAAcJdgcVEgDYAAAXAAUJ4gYqRADmAAAWAAcJxwYVEgDYAAAYAAEJtQlW2QAtAAAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Demonspecial:BAAALgAECgkJBwAAAA==.Denastus:BAAALgADCgEJAQAAAA==.Dethknyght:BAAALgAECgkJCgABLgAFFAUJDwABAIcdAA==.Detoxin:BAAALgAECgIJAgAAAA==.Devick:BAAALgAECgEJAQAAAA==.',
Di='Dinta:BAABLgAECn8wAAIGAAkJCRlSMgBZAgAGAAkJCRlSMgBZAgAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAAALgAECgUJBwAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgADCgYJBgAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8eAAIBAAkJRBNAEQDxAQABAAkJRBNAEQDxAQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8jAAIZAAgJGg3OGACPAQAZAAgJGg3OGACPAQAAAA==.Dummblond:BAAALgAFFAIJAwAAAA==.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAABLgAECn8WAAIaAAcJohopSACDAQAaAAcJohopSACDAQAAAA==.',
Dy='Dyonesa:BAAALgAECgQJBAAAAA==.Dysfunction:BAAALgAECggJDQAAAA==.',
Ea='Earthshield:BAAALgAECgYJDQABLgAECgkJOQAbADckAA==.',
Eg='Ego:BAABLgAECn8ZAAIbAAgJViK7BgDiAgAbAAgJViK7BgDiAgAAAA==.',
El='Elipto:BAAALgADCgcJGQAAAA==.Ellaana:BAAALgAECgQJCgAAAA==.Elotarra:BAAALgAECgEJAQAAAA==.Elowentinsel:BAAALgADCgkJLAAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgADCgYJCQAAAA==.',
En='Enduran:BAAALgAECgYJDQAAAA==.',
Er='Erasi:BAABLgAECn8qAAMcAAgJPgk2KQAwAQAcAAgJPgk2KQAwAQAdAAUJzwIHSQBqAAAAAA==.',
Es='Es:BAABLgAECn8UAAIUAAcJ8wTGpgA0AQAUAAcJ8wTGpgA0AQAAAA==.Escanorlion:BAAALgADCgcJBwAAAA==.Esttsumi:BAAALgAECgkJDwAAAA==.',
Eu='Euphia:BAAALgAECgUJDAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8iAAIIAAgJrhFuOQDJAQAIAAgJrhFuOQDJAQAAAA==.Exodiá:BAAALgADCgMJAwAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8kAAIGAAgJ+huqLAAFAgAGAAgJ+huqLAAFAgAAAA==.Faethe:BAAALgADCgMJAwABLgAECggJLAADACMkAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farmerpolly:BAAALgADCgMJAwAAAA==.Farwolf:BAABLgAECn8dAAIIAAgJLgqDVgBFAQAIAAgJLgqDVgBFAQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECgcJBwAAAA==.Fee:BAACLgAFFH8HAAIGAAQJyBkfFABsAQAGAAQJyBkfFABsAQAuAAQKfzoAAgYACQmSJAgDAEcDAAYACQmSJAgDAEcDAAAA.Fellyn:BAAALgADCgYJBwAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgADCggJCAAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.',
Fl='Flameheart:BAAALgAECgcJDgAAAA==.Fleathulhu:BAABLgAECn8vAAIdAAgJzR7yBgDAAgAdAAgJzR7yBgDAAgAAAA==.Flungpu:BAAALgADCgkJFwABLgAECggJJgAIAFYMAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAABLgAECn8WAAMaAAYJXwxnfQABAQAaAAYJGAxnfQABAQAeAAEJvRKXLQA4AAAAAA==.Foxieshoxie:BAAALgAECgEJAgAAAA==.',
Fr='Frontierland:BAAALgADCgcJDQAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgADCggJCAAAAA==.',
Fu='Furgy:BAAALgAECgEJAQAAAA==.Furrfoxsake:BAAALgADCggJCAAAAA==.Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAHAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn81AAIOAAkJfRbEAwAgAgAOAAkJfRbEAwAgAgAAAA==.',
Gh='Ghoulmaxing:BAAALgAECgEJBAAAAA==.Ghøulish:BAAALgADCgMJAwABLgAECggJJAAMAMcLAA==.',
Gi='Gimper:BAAALgADCgcJFwAAAA==.',
Gl='Glaistia:BAAALgADCgIJAgAAAA==.Glen:BAAALgAECgQJCgAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.Gormlaîth:BAAALgADCgkJCQAAAA==.',
Gr='Graeman:BAAALgADCgMJAwAAAA==.Grandpaslay:BAAALgAECgEJAQAAAA==.Greatpàw:BAAALgAECgEJAQAAAA==.Grisly:BAAALgADCgUJBQAAAA==.',
Gu='Gurrney:BAAALgADCgYJBgAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgAECgQJBgAAAA==.Habbypallie:BAAALgADCgUJEwAAAA==.Haimanist:BAABLgAECn8ZAAINAAgJlyAlAwDwAgANAAgJlyAlAwDwAgABLgAFFAUJDwABAIcdAA==.Halixan:BAABLgAECn8fAAIfAAgJFSP1AgCYAgAfAAgJFSP1AgCYAgAAAA==.Handlebardoc:BAACLgAFFH8HAAIUAAMJHBx8WwD5AAAUAAMJHBx8WwD5AAAuAAQKfzcAAhQACQldIhkKAOgCABQACQldIhkKAOgCAAAA.Harmoni:BAAALgAECgIJAgABLgAECggJLAADACMkAA==.Hatorade:BAAALgAECgUJBQAAAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgAECgkJAwAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgQJCgAAAA==.',
Ho='Holyname:BAAALgAECgEJAQAAAA==.Holysim:BAAALgAECgEJAQAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgAECgIJAgAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8rAAMaAAkJJwt5VABgAQAaAAkJnAh5VABgAQAeAAQJIxLrFwCsAAAAAA==.',
Ir='Ironfizt:BAAALgAECggJDwABLgAECggJHgAgAAQZAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.',
Iu='Iudex:BAAALgAECgYJBwAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAABLgAECn85AAMbAAkJNyRFAgBYAwAbAAkJNyRFAgBYAwAGAAUJzA5PtQDIAAAAAA==.Jarvy:BAAALgAECggJCAAAAA==.',
Je='Jedavon:BAAALgADCgkJLQAAAA==.Jerreden:BAAALgADCgYJBgAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.',
Ji='Jiangshi:BAAALgADCgkJCQAAAA==.Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ka='Kaazel:BAABLgAECn8mAAIIAAgJVgx6RQB5AQAIAAgJVgx6RQB5AQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgYJEgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgAECgMJBQAAAA==.Kamsham:BAAALgADCgUJBQAAAA==.Karite:BAABLgAECn8uAAIhAAkJkyLTAADqAgAhAAkJkyLTAADqAgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAIPAAgJSBmkEgAdAgAPAAgJSBmkEgAdAgAAAA==.Katyla:BAAALgADCgQJBAABLgAECgkJMQAIAOsMAA==.Kazar:BAAALgADCgQJCAAAAA==.Kazenoth:BAABLgAECn8pAAMRAAgJfxopGADGAQARAAgJfxopGADGAQAiAAEJbxHELwAxAAAAAA==.',
Ke='Kellement:BAAALgAECgMJAwAAAA==.Ken:BAAALgAECgQJBgABLgAECggJLwAaAN8YAA==.Kennychaoss:BAAALgAECggJEwAAAA==.',
Ki='Kille:BAAALgAECgUJCAAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Kobeqt:BAAALgAECgEJAQAAAA==.Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn8jAAIJAAgJngruKAAtAQAJAAgJngruKAAtAQAAAA==.Kostazu:BAABLgAECn8zAAIjAAgJYhEVJwBcAQAjAAgJYhEVJwBcAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAFFAQJBwAGAMgZAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAECggJLwAdAM0eAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAgAAAA==.',
La='Laity:BAABLgAECn8tAAIGAAgJvh6AHwBHAgAGAAgJvh6AHwBHAgAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Laraithe:BAAALgADCgEJAQAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgAECgEJAQAAAA==.Lazraar:BAAALgAECgEJAQAAAA==.Lazylaz:BAABLgAECn8rAAIVAAkJmyJZAQD+AgAVAAkJmyJZAQD+AgABLgAFFAYJHAAUALseAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAABLgAECn8XAAIfAAcJHR2GCADWAQAfAAcJHR2GCADWAQAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJBwAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAABLgAECn8WAAMXAAUJjhVAIwD3AAAXAAUJjhVAIwD3AAAYAAUJhAh7mQCXAAAAAA==.Lifebloom:BAAALgAECgIJAgABLgAECgkJOQAbADckAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAECgkJFgAZAOYdAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8xAAIIAAkJ6wxiNAC4AQAIAAkJ6wxiNAC4AQAAAA==.Livedcargox:BAAALgAECgYJBgAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgADCgcJBwAAAA==.',
Ly='Lycanbyte:BAAALgADCgkJMgAAAA==.Lylith:BAABLgAECn8sAAMXAAgJpBZ5EAC6AQAXAAgJpBZ5EAC6AQAYAAQJawWetQBeAAAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJBAAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Magdalena:BAABLgAECn8ZAAIIAAcJVQ5PVQBIAQAIAAcJVQ5PVQBIAQAAAA==.Magehawk:BAAALgAECgUJBAAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magnólia:BAABLgAECn8fAAICAAgJ2yNFDQCeAgACAAgJ2yNFDQCeAgAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Makima:BAAALgADCgcJCQABLgAECggJHgADAM0iAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Maribelle:BAAALgAECgMJAwABLgAECggJLAADACMkAA==.Marrent:BAAALgADCgcJGQAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJBQAAAA==.Mazeltov:BAABLgAECn8WAAIKAAgJPRrNDgAcAgAKAAgJPRrNDgAcAgAAAA==.',
Me='Melomel:BAABLgAECn8XAAIfAAYJEBA6FAD5AAAfAAYJEBA6FAD5AAAAAA==.Melonsquezer:BAABLgAECn8uAAMNAAkJLRy2BABmAgANAAkJLRy2BABmAgAGAAEJ2RPeMwE9AAAAAA==.Menmei:BAABLgAECn8XAAIIAAYJXguybgAGAQAIAAYJXguybgAGAQAAAA==.Mexicanrage:BAAALgADCgQJBAAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgAECgMJBQAAAA==.Minien:BAABLgAECn8rAAMjAAgJaxyDFgDeAQAjAAgJeBiDFgDeAQAfAAcJgBoLCwCbAQAAAA==.Minko:BAABLgAECn8iAAIIAAkJshiDHQAmAgAIAAkJshiDHQAmAgAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAECgkJJAADAGIPAA==.',
Mo='Modelo:BAAALgAECgYJBgAAAA==.Molulu:BAAALgADCgQJBAABLgAECgQJBAAHAAAAAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn8zAAIkAAgJgh5UAwBeAgAkAAgJgh5UAwBeAgAAAA==.Morillic:BAAALgAECgYJEQABLgAECggJGgAcABkWAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgADCgEJAQAAAA==.',
Ms='Mstrcrowly:BAABLgAECn8bAAMaAAYJmyEvLQDlAQAaAAYJmyEvLQDlAQAlAAIJvhwGIgBEAAAAAA==.',
Mu='Mustachjones:BAABLgAECn8rAAIaAAkJDBoIIAAnAgAaAAkJDBoIIAAnAgAAAA==.',
My='Myros:BAABLgAECn8uAAMDAAkJfBUeNQACAgADAAkJfBUeNQACAgALAAEJ8gUcDgArAAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgADCggJBwAAAA==.Narestor:BAABLgAECn8YAAISAAgJHRPBMQDlAQASAAgJHRPBMQDlAQABLgAECgYJFAARAEoIAA==.Navras:BAAALgADCgIJAgAAAA==.Nazurend:BAABLgAECn8WAAIDAAcJlxLmaABqAQADAAcJlxLmaABqAQAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAECgcJDQAAAA==.Nero:BAABLgAECn8nAAIXAAkJTyHLAwDMAgAXAAkJTyHLAwDMAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMaAAgJNAUjfQBhAQAaAAgJNAUjfQBhAQAeAAIJywFjZgBDAAAAAA==.Nimuerose:BAAALgADCgMJAwAAAA==.',
No='Nortree:BAABLgAECn8WAAIMAAYJ6BLNPwBKAQAMAAYJ6BLNPwBKAQAAAA==.Nost:BAABLgAECn8lAAIGAAgJDhzEJQAkAgAGAAgJDhzEJQAkAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.',
Nu='Nulwyrm:BAABLgAECn8fAAIRAAgJURgvFwDRAQARAAgJURgvFwDRAQAAAA==.Numira:BAAALgADCgMJAwAAAA==.',
Ny='Nyyrivik:BAAALgADCgkJDwAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8tAAICAAgJRR/LDQCYAgACAAgJRR/LDQCYAgAAAA==.',
Oh='Ohitsadragon:BAABLgAECn8ZAAIQAAcJwRYUBwCLAQAQAAcJwRYUBwCLAQAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAHAAAAAA==.',
Ow='Owl:BAABLgAECn8fAAIlAAkJAwzICQBXAQAlAAkJAwzICQBXAQAAAA==.Owlcatraz:BAAALgAFFAIJAgAAAA==.',
Pa='Paendrag:BAAALgADCgUJBQAAAA==.Panadarama:BAACLgAFFH8PAAIBAAUJhx2fDQBfAQABAAUJhx2fDQBfAQAuAAQKfygAAgEACAkWJWgEAEUDAAEACAkWJWgEAEUDAAAA.Panteragon:BAABLgAECn8WAAIZAAYJqgfYKAAFAQAZAAYJqgfYKAAFAQAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAAALgAECgYJDwAAAA==.',
Pe='Periwinkle:BAABLgAECn8dAAIdAAcJIxFaHwCAAQAdAAcJIxFaHwCAAQAAAA==.Persaud:BAABLgAECn8aAAMeAAkJbhjbDwDRAQAeAAcJnhLbDwDRAQAaAAUJOBxIPgCkAQAAAA==.',
Ph='Phidra:BAABLgAECn8uAAMCAAkJRg2MLgChAQACAAkJRg2MLgChAQAjAAQJTga/agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgAECgQJBAAHAAAAAA==.Phranky:BAAALgAECgEJAwABLgAECgIJBAAHAAAAAA==.',
Pi='Pixiebrew:BAAALgAECgUJDAAAAA==.',
Pl='Plutrax:BAAALgAECgIJAgAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.',
Pr='Predatorc:BAABLgAECn8dAAIIAAkJaAqIUABWAQAIAAkJaAqIUABWAQAAAA==.Primevil:BAAALgAECgYJBgAAAA==.Primevl:BAAALgADCgQJBAAAAA==.Primévil:BAABLgAECn8pAAIYAAgJVgvGXQAdAQAYAAgJVgvGXQAdAQAAAA==.',
Pu='Puma:BAAALgAECgYJEwAAAA==.',
['Pí']='Píp:BAAALgADCggJDQAAAA==.',
Qu='Quarz:BAAALgAECgIJAwAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.',
Ra='Raediant:BAAALgAECgUJBwABLgAECgkJHgABAEQTAA==.Raelek:BAAALgAECgQJBAAAAA==.Ragethecage:BAAALgADCgMJAwAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8lAAMSAAgJPBzrEAAmAgASAAgJPBzrEAAmAgAKAAcJrRTeEwBhAQAAAA==.Raquel:BAABLgAECn8jAAICAAkJJAtvRwBkAQACAAkJJAtvRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAAALgAECgMJAwAAAA==.',
Re='Rede:BAAALgAECgIJAwAAAA==.Rein:BAABLgAECn8kAAIDAAkJYg+kPADmAQADAAkJYg+kPADmAQAAAA==.Relieff:BAAALgAECgUJCQAAAA==.Relmin:BAAALgADCgkJEwAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.',
Ri='Rio:BAABLgAECn8nAAIXAAgJABd1DwDJAQAXAAgJABd1DwDJAQAAAA==.Ris:BAABLgAECn8oAAIDAAkJKR+NGgCBAgADAAkJKR+NGgCBAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgADCgQJBAAAAA==.Roguesgambit:BAAALgAECgkJCQAAAA==.Roknathar:BAABLgAECn8nAAIkAAgJpyXwAQC1AgAkAAgJpyXwAQC1AgAAAA==.Ronburrgandy:BAAALgAECgEJAQAAAA==.Ronilf:BAABLgAECn8eAAIgAAgJBBnlDgDtAQAgAAgJBBnlDgDtAQAAAA==.Rono:BAAALgADCgYJDAAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8oAAMcAAkJURwaDABDAgAcAAkJURwaDABDAgAdAAIJyhN8iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgADCgkJEAAAAA==.Rukaza:BAAALgAECgEJAQABLgAFFAQJBwAYANMUAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Saerenity:BAAALgAECgMJAwAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgADCggJFQAAAA==.Sana:BAABLgAECn8mAAIjAAgJfB+1DQBCAgAjAAgJfB+1DQBCAgAAAA==.Saphihr:BAAALgADCgYJBgAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAHAAAAAA==.',
Se='Sedo:BAAALgAECgQJBQAAAA==.Selenis:BAAALgAECgEJAwABLgAECgkJKwAUACwkAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shamainiac:BAABLgAECn8zAAIjAAgJwBaoHQCfAQAjAAgJwBaoHQCfAQAAAA==.Shamspecial:BAAALgAECgkJCQAAAA==.Shaomai:BAABLgAECn8rAAMjAAkJ9SCSBQDMAgAjAAkJ9SCSBQDMAgACAAQJLw0acwDDAAAAAA==.Sharper:BAABLgAECn8XAAIYAAcJaRyBNQClAQAYAAcJaRyBNQClAQABLgAFFAMJBwAUABwcAA==.Shep:BAAALgAECgMJAwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shiok:BAAALgADCggJFwAAAA==.Shoknorris:BAAALgADCgkJCQAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgQJCQAAAA==.Silverwin:BAABLgAECn8XAAIdAAYJNQ96LgAQAQAdAAYJNQ96LgAQAQAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8jAAImAAkJHRldAQBXAgAmAAkJHRldAQBXAgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJCgAAAA==.Smitted:BAAALgAECgYJEgAAAA==.Smitty:BAABLgAECn8VAAMBAAgJnRWyGACjAQABAAgJdxSyGACjAQAnAAgJQhBWHgBpAQAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAAALgAECgYJCwAAAA==.Sophiaa:BAAALgADCgcJBgAAAA==.Sorn:BAABLgAECn8aAAINAAcJMhNMEgBJAQANAAcJMhNMEgBJAQAAAA==.',
Sp='Spaarkle:BAAALgAECgYJBwAAAA==.Specialheist:BAAALgAECgkJEwAAAA==.Spectrehawk:BAAALgAECgYJBgABLgAFFAQJCwAEAGQTAA==.Speçtre:BAACLgAFFH8LAAIEAAQJZBM0DgAhAQAEAAQJZBM0DgAhAQAuAAQKfycAAwQACQkiG1kJAC8CAAQACAkDHlkJAC8CABQAAQn+BqsGAT0AAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgEJAQAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAABLgAECn8aAAIcAAgJGRYPFgDIAQAcAAgJGRYPFgDIAQAAAA==.Stormglaive:BAABLgAECn8aAAMXAAcJPxU8HQDWAQAXAAcJPxU8HQDWAQAYAAEJUwPt6QAoAAAAAA==.Stupidity:BAABLgAECn8kAAMcAAgJWBrpFwAkAgAcAAYJiCDpFwAkAgAdAAIJhBdDRQCAAAAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn8uAAMPAAkJXx8cBQAEAwAPAAkJXx8cBQAEAwAnAAYJWBMhHwBiAQAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgADCgUJBQABLgAECggJLAADACMkAA==.Tarysha:BAAALgAECgcJEgAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn8rAAIoAAkJtRDpEQBcAQAoAAkJtRDpEQBcAQAAAA==.Tayoma:BAAALgAECgEJAQAAAA==.Tazara:BAAALgAECgEJAQAAAA==.',
Te='Tealth:BAAALgAECgYJBgAAAA==.Ted:BAABLgAECn8bAAIjAAcJTBQoKQBPAQAjAAcJTBQoKQBPAQAAAA==.Tehgrimza:BAABLgAECn8dAAMaAAgJOhPKSgB8AQAaAAgJOhPKSgB8AQAeAAEJrxCDdAAwAAAAAA==.Teias:BAAALgAECggJCgABLgAFFAIJBwAdAEMhAA==.Teka:BAAALgADCgMJAwAAAA==.Temu:BAAALgAECgYJCAABLgAECggJHgADAM0iAA==.Tet:BAAALgAFFAIJAgAAAA==.Tevia:BAABLgAECn8tAAIpAAkJ4hiMBwArAgApAAkJ4hiMBwArAgAAAA==.',
Th='Thalip:BAAALgAECgQJBgAAAA==.Thokmay:BAABLgAECn8iAAInAAgJIg+0JQAyAQAnAAgJIg+0JQAyAQAAAA==.Thorel:BAAALgAECgQJBAAAAA==.Thornar:BAAALgAECgUJBQAAAA==.Thunden:BAAALgAECgUJBAAAAA==.',
Ti='Tiandrinna:BAABLgAECn8hAAILAAkJCBtqAQA3AgALAAkJCBtqAQA3AgAAAA==.Tightywhitey:BAAALgAECgYJBwAAAA==.Timkaoss:BAABLgAECn8WAAMMAAYJtxR3UABkAQAMAAYJtxR3UABkAQAJAAMJNQfCWwBPAAAAAA==.Timmyjudge:BAAALgAECgYJCAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAABLgAECn8XAAIKAAYJ9wQjKQCiAAAKAAYJ9wQjKQCiAAAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgkJFgAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgEJAgABLgAECggJHwACANsjAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgAECgMJAwAAAA==.Trixterwolf:BAAALgADCgUJBwAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAACLgAFFH8FAAIDAAIJ/weoegCXAAADAAIJ/weoegCXAAAuAAQKfysAAgMACQm2F2MtACECAAMACQm2F2MtACECAAAA.',
Ty='Tygrassar:BAAALgAECgIJAgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8nAAIdAAkJTxonCQCNAgAdAAkJTxonCQCNAgAAAA==.',
['Tä']='Täd:BAAALgAECgUJCAAAAA==.',
Va='Vaelena:BAAALgADCgMJAwAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAAALgAECgYJEQAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAABLgAECn8hAAIGAAgJVx7VIgA0AgAGAAgJVx7VIgA0AgAAAA==.Valicous:BAAALgADCgkJLQAAAA==.Valyerian:BAABLgAECn8uAAISAAgJ5hsOFgCcAgASAAgJ5hsOFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgkJHgAEAGMiAA==.Vandevoker:BAAALgAECgQJCAABLgAECgkJHgAEAGMiAA==.Vanserra:BAAALgADCgcJEAAAAA==.Varregory:BAAALgADCgQJBAAAAA==.Vaxas:BAABLgAECn8jAAIGAAgJ1h+jHABXAgAGAAgJ1h+jHABXAgAAAA==.Vaxasus:BAAALgAECgEJAQAAAA==.Vaylorian:BAAALgAECgYJEQAAAA==.Vaült:BAABLgAECn8mAAMbAAkJmxW8EQA8AgAbAAkJmxW8EQA8AgAGAAMJPwYbEgFzAAAAAA==.',
Ve='Verianna:BAABLgAECn8rAAQUAAkJLCQXHABbAgAUAAgJZiEXHABbAgAEAAQJ9CQBEQClAQAFAAMJhBpwEADsAAAAAA==.Vexmorphis:BAAALgADCgYJBQABLgAECgkJHgAGAJwSAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgAECgQJBAAAAA==.',
Vr='Vraknaar:BAAALgADCgQJBAAAAA==.',
Vt='Vtown:BAAALgADCgYJFQAAAA==.',
Wa='Wadumu:BAABLgAECn8kAAMMAAgJxwsOaQAYAQAMAAYJVg4OaQAYAQAoAAgJWQvuGgD1AAAAAA==.Wagwanmist:BAABLgAECn8tAAIPAAgJtBl+EQAqAgAPAAgJtBl+EQAqAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warvegas:BAAALgAECgQJBgAAAA==.Warwulf:BAAALgAECgQJBAABLgAECggJJQASADwcAA==.Water:BAAALgADCgEJAQAAAA==.',
Wi='Willowy:BAABLgAECn8sAAIDAAgJIyR5FACoAgADAAgJIyR5FACoAgAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8bAAQCAAUJ4hMVVAD7AAACAAUJ4hMVVAD7AAAjAAQJzAdaaACiAAAfAAEJngodJwAxAAAAAA==.',
Xa='Xaerius:BAABLgAECn8uAAMSAAkJ5BPSFAD+AQASAAkJ5BPSFAD+AQApAAEJ6wWGVQApAAAAAA==.Xalatath:BAAALgADCgcJDQAAAA==.Xan:BAABLgAECn8gAAIDAAkJyRebNwD4AQADAAkJyRebNwD4AQAAAA==.Xann:BAAALgAECgIJAgAAAA==.Xannen:BAAALgADCgkJCQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAAALgAECgcJBwAAAA==.Xashadin:BAAALgAECgcJBwAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIDAAcJJiNIPQCCAgADAAcJJiNIPQCCAgAAAA==.',
Xo='Xog:BAAALgAECgIJAgAAAA==.',
Ya='Yarman:BAABLgAECn8XAAIBAAYJHQ+bNADwAAABAAYJHQ+bNADwAAAAAA==.',
Ye='Yeaforpie:BAABLgAECn8XAAMaAAYJmA6OeQAJAQAaAAYJ/wyOeQAJAQAlAAMJDQ/eGAB2AAAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAABLgAECn8YAAIbAAgJ7RTJHgDAAQAbAAgJ7RTJHgDAAQAAAA==.',
Yo='Yoshial:BAAALgAECgQJBAAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAABLgAECn8oAAMcAAgJjhQwHgDoAQAcAAgJjhQwHgDoAQATAAYJPA2DLAAUAQAAAA==.',
Ze='Zealins:BAAALgADCgUJCAAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQAAAA==.Ziv:BAABLgAECn80AAIMAAkJKiBvBQAwAwAMAAkJKiBvBQAwAwABLgAECgkJFgAZAOYdAA==.Ziyn:BAABLgAECn8WAAMZAAkJ5h1HBAC2AgAZAAkJ5h1HBAC2AgAIAAYJrhoITwBaAQAAAA==.',
['Ôa']='Ôath:BAAALgAECgEJAQAAAA==.',
['Ÿe']='Ÿeñnefer:BAAALgADCgEJAQAAAA==.',
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
