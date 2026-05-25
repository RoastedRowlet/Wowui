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

local lookup = {'Monk-Brewmaster','Shaman-Restoration','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Mage-Fire','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Warrior-Arms','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Priest-Discipline','DeathKnight-Unholy','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Warlock-Demonology','Druid-Guardian','Paladin-Holy','Priest-Shadow','Priest-Holy','Warlock-Destruction','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Evoker-Preservation','Shaman-Elemental','Hunter-Marksmanship','Warlock-Affliction','Mage-Arcane','Monk-Windwalker',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aarztok:BAAALgAECgUJBQABLgAFFAYJFQABACwdAA==.',
Ac='Achiella:BAAALgADCgIJAgAAAA==.',
Ad='Advisor:BAACLgAFFH8KAAICAAQJkRCSKwD8AAACAAQJkRCSKwD8AAAuAAQKfzEAAgIACQmcJG0JAOECAAIACQmcJG0JAOECAAAA.',
Ae='Aería:BAAALgAECgYJDwAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgAECgEJAQAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgADCgcJBwAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgADCgcJEAAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgADCgkJHAAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Andolas:BAAALgADCgMJAwAAAA==.Angelicuss:BAAALgAECgQJBQABLgAECgkJNAADALUjAA==.Annya:BAAALgAECgYJBgAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCwAAAA==.Arkahera:BAAALgAECgQJBQABLgAFFAYJFQABACwdAA==.Arolder:BAABLgAECn8mAAMEAAkJqyFWBADPAgAEAAkJdSFWBADPAgAFAAcJZB3dAwA6AgAAAA==.Arredin:BAAALgADCgYJBgAAAA==.Arturium:BAAALgADCgYJCwAAAA==.',
As='Astayuno:BAAALgADCgQJBAAAAA==.',
At='Atabey:BAABLgAECn87AAIGAAkJICLcCgD0AgAGAAkJICLcCgD0AgABLgABCgMJAwAHAAAAAA==.Atimusk:BAAALgADCggJDwABLgAECgMJAwAHAAAAAA==.Atoadaso:BAAALgAECgQJBAAAAA==.Attretes:BAAALgADCgcJDwAAAA==.',
Az='Azcowboy:BAAALgAECgMJCwAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgAECgMJAwAAAA==.',
Ba='Badco:BAAALgAECgQJBAAAAA==.Balacheck:BAABLgAECn8XAAIIAAYJyAQFnADRAAAIAAYJyAQFnADRAAAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgADCgQJCgAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAABLgAECn8qAAIJAAkJbxySCQCWAgAJAAkJbxySCQCWAgAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgYJFAAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAADAKAcAA==.',
Bi='Bigbadwoof:BAAALgADCgYJGQAAAA==.Bighog:BAABLgAFFH8TAAIKAAQJ8iCTBwB7AQAKAAQJ8iCTBwB7AQAAAA==.Bipbipbup:BAAALgAECgEJAQAAAA==.',
Bj='Björn:BAAALgADCgcJBwAAAA==.',
Bl='Blaazzin:BAAALgADCgcJHgAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Bloomzy:BAABLgAECn8uAAMDAAkJbhoAKgBVAgADAAkJbhoAKgBVAgALAAIJehtaCgCfAAAAAA==.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAAALgADCgYJCgAAAA==.Boombástic:BAABLgAECn8oAAMJAAkJaQ9UJAB6AQAJAAgJMhBUJAB6AQAMAAIJ0A/LlABnAAAAAA==.Boomco:BAAALgAECgcJDgAAAA==.Bors:BAAALgADCgUJEAAAAA==.Boulderholdr:BAAALgAECgQJCgAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAAALgAECgYJEgAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAINAAkJyRmeCgAkAgANAAkJyRmeCgAkAgAAAA==.Bryda:BAAALgAECgQJCgAAAA==.',
Bu='Bubblez:BAAALgADCgYJCQAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAAALgAECgQJCgAAAA==.',
Ca='Cajbo:BAABLgAECn8vAAIOAAgJzR4pAwBhAgAOAAgJzR4pAwBhAgAAAA==.Calyssa:BAABLgAECn8eAAIGAAgJ6w72bwBuAQAGAAgJ6w72bwBuAQAAAA==.Candyflöss:BAACLgAFFH8JAAIKAAQJbBwrCwBAAQAKAAQJbBwrCwBAAQAuAAQKfxUAAwoABgkwI7kMAPgBAAoABgkwI7kMAPgBAA8AAQkLEFVeADMAAAAA.Capmkrunch:BAAALgAECgEJAgABLgAECgIJBAAHAAAAAA==.Caralynn:BAAALgAECgUJBQAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAABLgAECn9EAAIQAAkJGyEMBABNAwAQAAkJGyEMBABNAwAAAA==.Cathelina:BAAALgADCggJDwAAAA==.Cathom:BAAALgAECgQJCQAAAA==.',
Ch='Charcasm:BAAALgAECgYJCAAAAA==.Charizaard:BAAALgAECgYJCQAAAA==.Charizaardx:BAACLgAFFH8MAAMRAAUJIQUSBgDGAAASAAQJQQQvLQDhAAARAAQJWwUSBgDGAAAuAAQKf0AAAxEACQkFGBAGAMwBABEACAmWFRAGAMwBABIACAnRFPYlAI0BAAAA.Chevytron:BAAALgAECgYJEwAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8bAAMTAAcJSxDqTgDiAAATAAYJYQ/qTgDiAAAKAAMJzgxHOwBcAAAAAA==.Clives:BAAALgAECgEJAQAAAA==.Clmx:BAAALgADCgIJAgAAAA==.Clément:BAAALgADCgUJBQAAAA==.',
Co='Coffeebeans:BAABLgAECn8iAAMMAAgJExbjPgCnAQAMAAcJfxTjPgCnAQAJAAgJwAs/LQA/AQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowkiller:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgYJCgAAAA==.Crimsonthot:BAAALgADCgEJAQAAAA==.Crogan:BAAALgAECgcJEAAAAA==.Crysiscane:BAAALgADCgYJBQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQABLgAECgIJBAAHAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgADCggJCQAAAA==.Dagul:BAAALgAECgQJBAAAAA==.Dalna:BAABLgAECn8sAAIQAAgJqBJoJAC1AQAQAAgJqBJoJAC1AQAAAA==.Danilex:BAABLgAECn8cAAIDAAgJCx9pSABeAgADAAgJCx9pSABeAgABLgAFFAgJJgAUALwZAA==.Danksoul:BAAALgADCgUJBQABLgAFFAIJAgAHAAAAAA==.Darcorin:BAABLgAECn8fAAIVAAgJIBaJWwCRAQAVAAgJIBaJWwCRAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAABLgAECn8ZAAIIAAcJMQeKegAbAQAIAAcJMQeKegAbAQAAAA==.Darksaber:BAAALgAECgQJCgAAAA==.Dasthodan:BAAALgAECgMJBgAAAA==.Dayne:BAAALgAECgcJDQAAAA==.',
Dc='Dctrpepper:BAAALgAECgIJAgAAAA==.',
De='Deathcore:BAAALgADCgYJCgAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8uAAQMAAkJBwbDYADzAAAMAAkJBwbDYADzAAAJAAkJWAMYPQDqAAAWAAIJhQCIOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Delvisprezly:BAAALgAECgIJBAAAAA==.Demonica:BAABLgAECn8dAAQXAAgJkQYFEwDxAAAXAAgJ+wUFEwDxAAAYAAUJ4gYqRADmAAAZAAEJtQm/8gAtAAAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Demonspecial:BAAALgAECgkJBwAAAA==.Denastus:BAAALgADCgEJAQAAAA==.Dethknyght:BAAALgAECgkJCgABLgAFFAYJFQABACwdAA==.Detoxin:BAAALgAECgIJAgAAAA==.Devick:BAAALgAECgEJAQAAAA==.',
Di='Dinta:BAABLgAECn8yAAIGAAkJNBlSMgBZAgAGAAkJNBlSMgBZAgAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAAALgAECgcJDgAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgADCgYJBgAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8fAAIBAAkJLhUyEwD6AQABAAkJLhUyEwD6AQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8sAAIaAAkJTg0XFQDgAQAaAAkJTg0XFQDgAQAAAA==.Dummblond:BAABLgAFFH8HAAIMAAQJ5wL9PQCZAAAMAAQJ5wL9PQCZAAAAAA==.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAABLgAECn8XAAIbAAcJKB0eRwCuAQAbAAcJKB0eRwCuAQAAAA==.',
Dy='Dyonesa:BAAALgAECgQJBAAAAA==.Dysfunction:BAABLgAECn8UAAIcAAgJwRFmFgBhAQAcAAgJwRFmFgBhAQAAAA==.',
Ea='Earthshield:BAAALgAECgYJDQABLgAECgkJOQAdADckAA==.',
Eg='Ego:BAABLgAECn8dAAIdAAgJoyJQCADhAgAdAAgJoyJQCADhAgAAAA==.',
El='Elipto:BAAALgAECgUJBQAAAA==.Ellaana:BAAALgAECgQJCgAAAA==.Elotarra:BAAALgAECgEJAQAAAA==.Elowentinsel:BAAALgADCgkJLAAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgADCgYJCQAAAA==.',
En='Enduran:BAAALgAECgYJDQAAAA==.',
Er='Erasi:BAABLgAECn8zAAMeAAkJVArLIgCJAQAeAAkJVArLIgCJAQAfAAUJzwINUQBpAAAAAA==.',
Es='Es:BAABLgAECn8UAAIVAAcJ8wTGpgA0AQAVAAcJ8wTGpgA0AQAAAA==.Escanorlion:BAAALgADCgcJBwAAAA==.Esileda:BAAALgAECgQJBAAAAA==.Esttsumi:BAAALgAECgkJDwAAAA==.',
Eu='Euphia:BAAALgAECgUJDAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8pAAIIAAkJqhBuOQDJAQAIAAkJqhBuOQDJAQAAAA==.Exodiá:BAAALgADCgMJAwAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8kAAIGAAgJ+huXOgD4AQAGAAgJ+huXOgD4AQAAAA==.Faethe:BAAALgADCgMJAwABLgAECgkJNAADALUjAA==.Faithfulpain:BAAALgADCgYJBgAAAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farmerpolly:BAAALgADCgMJAwAAAA==.Farwolf:BAABLgAECn8gAAIIAAgJLgqsYQBVAQAIAAgJLgqsYQBVAQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECgcJBwAAAA==.Fee:BAACLgAFFH8MAAIGAAUJoCLQEACVAQAGAAUJoCLQEACVAQAuAAQKfzsAAgYACQmSJNUEAD0DAAYACQmSJNUEAD0DAAAA.Fellyn:BAAALgAECgQJBAAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgAECgIJAgAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.Fishstick:BAAALgAECgQJBAAAAA==.',
Fl='Flameheart:BAAALgAECgcJEgAAAA==.Fleathulhu:BAACLgAFFH8FAAIfAAIJ3woTIwBzAAAfAAIJ3woTIwBzAAAuAAQKfzIAAh8ACQmfHJ4GAOgCAB8ACQmfHJ4GAOgCAAAA.Flungpu:BAAALgADCgkJFwABLgAECggJKAAIAFYMAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAABLgAECn8YAAMbAAYJXwx+kgABAQAbAAYJGAx+kgABAQAgAAEJvRIkNAA2AAAAAA==.Foxieshoxie:BAAALgAECgEJAwAAAA==.',
Fr='Frontierland:BAAALgADCgcJDQAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgADCggJCAAAAA==.',
Fu='Furgy:BAAALgAECgEJAQAAAA==.Furrfoxsake:BAAALgAECgQJBQAAAA==.Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAHAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn83AAIOAAkJhRb5BAARAgAOAAkJhRb5BAARAgAAAA==.',
Gh='Ghoulmaxing:BAAALgAECgEJBQABLgAECgcJBwAHAAAAAA==.Ghøulish:BAAALgAECgUJBgABLgAECggJLAAMAMsLAA==.',
Gi='Gimper:BAAALgADCgcJFwAAAA==.',
Gl='Glaistia:BAAALgADCgIJAgAAAA==.Glen:BAAALgAECgQJCgAAAA==.Glowstik:BAAALgAECgQJBAAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.Gormlaîth:BAAALgAECgMJAwAAAA==.',
Gr='Graeman:BAAALgADCgMJAwAAAA==.Grandpaslay:BAAALgAECgMJAwAAAA==.Greatpàw:BAAALgAECgEJAQAAAA==.Grisly:BAAALgADCgUJBQAAAA==.',
Gu='Gurrney:BAAALgADCgYJBgAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgAECgUJCgAAAA==.Habbypallie:BAAALgADCgYJFAAAAA==.Haimanist:BAABLgAECn8ZAAINAAgJliAlAwDwAgANAAgJliAlAwDwAgABLgAFFAYJFQABACwdAA==.Halixan:BAABLgAECn8fAAIhAAgJFiOKBACCAgAhAAgJFiOKBACCAgAAAA==.Handlebardoc:BAACLgAFFH8KAAIVAAMJ0B2OZgD+AAAVAAMJ0B2OZgD+AAAuAAQKf0AAAhUACQleIukMAOYCABUACQleIukMAOYCAAAA.Harmoni:BAAALgAECgIJAgABLgAECgkJNAADALUjAA==.Hatorade:BAAALgAECgUJBQAAAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgAECgkJAwAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgYJEAAAAA==.',
Ho='Holyname:BAAALgAECgEJAQAAAA==.Holysim:BAAALgAECgEJAQAAAA==.',
Hu='Hunteð:BAAALgAECgEJAQAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgAECgIJAgAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8wAAMgAAkJDQybEQAAAQAbAAkJ0AgIXwBtAQAgAAYJ/w2bEQAAAQAAAA==.',
Ir='Ireus:BAAALgAECgIJAgAAAA==.Ironfizt:BAAALgAECggJDwABLgAECggJJQAiAOMZAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.',
Iu='Iudex:BAAALgAECgYJBwAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAABLgAECn85AAMdAAkJNyRFAgBYAwAdAAkJNyRFAgBYAwAGAAUJzA4F1ADIAAAAAA==.Jarvy:BAAALgAECggJCAAAAA==.',
Je='Jedavon:BAAALgADCgkJLQAAAA==.Jerreden:BAAALgADCgYJBgAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.',
Ji='Jiangshi:BAAALgADCgkJCQAAAA==.Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ju='Justpwnedu:BAAALgAECgkJCgAAAA==.',
Ka='Kaazel:BAABLgAECn8oAAIIAAgJVgztVAB2AQAIAAgJVgztVAB2AQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgYJEgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgAECggJDQAAAA==.Kamsham:BAAALgADCgUJBQAAAA==.Karite:BAABLgAECn8zAAIjAAkJkyIzAQDaAgAjAAkJkyIzAQDaAgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAIQAAgJRxmKFwAfAgAQAAgJRxmKFwAfAgAAAA==.Karveila:BAAALgAECgQJBAAAAA==.Katyla:BAAALgADCgQJBAABLgAECgkJMwAIAOoMAA==.Kazar:BAAALgADCgQJCAAAAA==.Kazenoth:BAABLgAECn8qAAMSAAkJxxpuEwAiAgASAAkJxxpuEwAiAgAkAAEJbxHxNAAxAAAAAA==.',
Ke='Kellement:BAAALgAECgUJBQAAAA==.Ken:BAAALgAECggJDgABLgAECgkJMwAbAA4YAA==.Kennychaoss:BAABLgAECn8cAAMCAAkJMxbyFwBeAgACAAkJMxbyFwBeAgAlAAcJBQ1sOwAXAQAAAA==.',
Kh='Khrisbkreme:BAAALgAECgEJAQABLgAECgIJBAAHAAAAAA==.',
Ki='Kille:BAAALgAECgcJDwAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Kobeqt:BAAALgAECgEJAQAAAA==.Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn8qAAIJAAgJYAzmKwBHAQAJAAgJYAzmKwBHAQAAAA==.Kostazu:BAABLgAECn88AAIlAAkJ/w/6JgCHAQAlAAkJ/w/6JgCHAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAFFAUJDAAGAKAiAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAFFAIJBQAfAN8KAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAgAAAA==.',
La='Laity:BAABLgAECn81AAIGAAgJnSGlFwCXAgAGAAgJnSGlFwCXAgAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Laraithe:BAAALgADCgEJAQAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgAECgEJAQAAAA==.Lazraar:BAAALgAECgEJAQAAAA==.Lazylaz:BAABLgAECn8vAAIWAAkJNyRXAQAcAwAWAAkJNyRXAQAcAwABLgAFFAgJIgAVAAEeAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAABLgAECn8dAAIhAAcJBx9TCAANAgAhAAcJBx9TCAANAgAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJCQAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAABLgAECn8dAAMYAAYJuRcdHABgAQAYAAYJuRcdHABgAQAZAAUJhAhQrgCaAAAAAA==.Lifebloom:BAAALgAECgIJAgABLgAECgkJOQAdADckAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAFFAMJBgAaAGIfAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8zAAIIAAkJ6gx1QQCyAQAIAAkJ6gx1QQCyAQAAAA==.Livedcargox:BAAALgAECgYJBgAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgAECgEJAQAAAA==.',
Ly='Lycanbyte:BAAALgAECgMJAwAAAA==.Lylith:BAABLgAECn80AAMYAAkJLxZ6DgAIAgAYAAkJLxZ6DgAIAgAZAAQJawVyygBjAAAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJBAAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Maddicollins:BAAALgAECgYJBgABLgAFFAIJBQAGANISAA==.Magdalena:BAABLgAECn8hAAIIAAgJRw5lUACDAQAIAAgJRw5lUACDAQAAAA==.Magehawk:BAAALgAECgUJBAAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magmaface:BAAALgAECgYJBwAAAA==.Magnólia:BAABLgAECn8jAAICAAgJGiTkDwCoAgACAAgJGiTkDwCoAgAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Maithre:BAAALgAECgEJAQAAAA==.Makima:BAAALgADCgcJCQABLgAECggJHwADAM4iAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Maribelle:BAAALgAECgMJAwABLgAECgkJNAADALUjAA==.Marrent:BAAALgADCgcJGQAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJCAAAAA==.Mazeltov:BAABLgAECn8WAAIKAAgJPRrNDgAcAgAKAAgJPRrNDgAcAgAAAA==.',
Me='Melomel:BAABLgAECn8eAAIhAAYJ0xGRFQAiAQAhAAYJ0xGRFQAiAQAAAA==.Melonsquezer:BAABLgAECn8zAAMNAAkJsh4tBACZAgANAAkJsh4tBACZAgAGAAEJ2RPeMwE9AAAAAA==.Menmei:BAABLgAECn8eAAIIAAYJCw0XegAcAQAIAAYJCw0XegAcAQAAAA==.Mexicanrage:BAAALgADCgQJBAAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgAECgQJCQAAAA==.Minien:BAABLgAECn8yAAMlAAgJHB17HADRAQAlAAgJeRh7HADRAQAhAAcJrRwZDAC6AQAAAA==.Minko:BAABLgAECn8rAAIIAAkJIhtAFgB5AgAIAAkJIhtAFgB5AgAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAECgkJLQADAF4SAA==.',
Mo='Modelo:BAAALgAFFAEJAQAAAA==.Molulu:BAAALgADCgQJBAABLgAECgUJCQAHAAAAAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn88AAImAAkJLR2ZAgCiAgAmAAkJLR2ZAgCiAgAAAA==.Morillic:BAABLgAECn8YAAQnAAcJqxjfBwC4AQAnAAcJqxjfBwC4AQAgAAMJrA0MSACWAAAbAAIJMxSCCgFIAAABLgAECggJGgAeABgWAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgADCgEJAQAAAA==.',
Ms='Mstrcrowly:BAABLgAECn8cAAMbAAYJSiKvNADuAQAbAAYJSiKvNADuAQAnAAIJvhzHKwBEAAAAAA==.',
Mu='Mustachjones:BAABLgAECn80AAIbAAkJERxfGQByAgAbAAkJERxfGQByAgAAAA==.',
My='Myros:BAABLgAECn83AAMDAAkJhBWTOwAQAgADAAkJhBWTOwAQAgALAAEJ8gUfEAArAAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgADCggJBwAAAA==.Narestor:BAABLgAECn8YAAITAAgJHRPBMQDlAQATAAgJHRPBMQDlAQAAAA==.Nazervis:BAAALgAECgUJBQABLgAFFAgJIgAVAAEeAA==.Nazurend:BAABLgAECn8bAAIDAAcJmBJbdwBtAQADAAcJmBJbdwBtAQAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAECgcJDwAAAA==.Nemesîs:BAAALgADCgYJBgAAAA==.Nero:BAABLgAECn8nAAIYAAkJTyF9BQC8AgAYAAkJTyF9BQC8AgAAAA==.Nest:BAAALgADCgYJDQAAAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMbAAgJNAUjfQBhAQAbAAgJNAUjfQBhAQAgAAIJywFjZgBDAAAAAA==.Nimuerose:BAAALgADCgMJAwAAAA==.',
No='Nortree:BAABLgAECn8bAAIMAAYJ3RMbRQBYAQAMAAYJ3RMbRQBYAQAAAA==.Nost:BAABLgAECn8sAAIGAAgJDhy+MAAcAgAGAAgJDhy+MAAcAgAAAA==.Notalock:BAAALgADCgIJAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.',
Nu='Nulwyrm:BAABLgAECn8jAAISAAgJzxnJFwD4AQASAAgJzxnJFwD4AQAAAA==.Numira:BAAALgADCgMJAwAAAA==.',
Ny='Nyyrivik:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8tAAICAAgJRR9pEgCOAgACAAgJRR9pEgCOAgAAAA==.',
Oh='Ohitsadragon:BAABLgAECn8fAAIRAAcJSBcaCACQAQARAAcJSBcaCACQAQAAAA==.',
On='Ono:BAAALgAECgEJAQAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAHAAAAAA==.',
Ow='Owl:BAABLgAECn8fAAInAAkJAwxSDQBQAQAnAAkJAwxSDQBQAQAAAA==.Owlcatraz:BAABLgAFFH8JAAIMAAQJnwa6KwDnAAAMAAQJnwa6KwDnAAAAAA==.',
Pa='Paendrag:BAAALgADCgUJBQAAAA==.Panadarama:BAACLgAFFH8VAAIBAAYJLB0FBwDEAQABAAYJLB0FBwDEAQAuAAQKfygAAgEACAkWJWgEAEUDAAEACAkWJWgEAEUDAAAA.Pandmei:BAAALgADCgkJCQAAAA==.Panteragon:BAABLgAECn8cAAIaAAYJqgedMAAAAQAaAAYJqgedMAAAAQAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAABLgAECn8WAAIIAAYJwgYIjwDuAAAIAAYJwgYIjwDuAAAAAA==.',
Pe='Periwinkle:BAABLgAECn8eAAIfAAgJZg9rIQCUAQAfAAgJZg9rIQCUAQAAAA==.Persaud:BAACLgAFFH8GAAIbAAMJlAwUYQDVAAAbAAMJlAwUYQDVAAAuAAQKfxwAAyAACQkkGtsPANEBACAABwmeEtsPANEBABsABQn0HhFGALIBAAAA.',
Ph='Phidra:BAABLgAECn81AAMCAAkJRg1POACdAQACAAkJRg1POACdAQAlAAQJTga/agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgAECgUJCQAHAAAAAA==.Phranky:BAAALgAECgEJAwABLgAECgIJBAAHAAAAAA==.',
Pi='Pixiebrew:BAAALgAECgUJDAAAAA==.',
Pl='Plutrax:BAAALgAECgIJBAAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.',
Pr='Predatorc:BAABLgAECn8dAAIIAAkJaArHTgB9AQAIAAkJaArHTgB9AQAAAA==.Primevil:BAAALgAECgYJBgAAAA==.Primevl:BAAALgADCgQJBAAAAA==.Primévil:BAABLgAECn8yAAIZAAkJ2Qw4SACLAQAZAAkJ2Qw4SACLAQAAAA==.',
Pu='Puma:BAAALgAECgYJEwAAAA==.',
['Pí']='Píp:BAAALgADCggJDQAAAA==.',
Qu='Quarz:BAAALgAECgIJAwAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.',
Ra='Raediant:BAAALgAECgUJBwABLgAECgkJHwABAC4VAA==.Raelek:BAAALgAECgQJBAAAAA==.Ragethecage:BAAALgADCgMJAwAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8lAAMTAAgJPBycFgAVAgATAAgJPBycFgAVAgAKAAcJrRSCGABSAQAAAA==.Raquel:BAABLgAECn8jAAICAAkJJQtvRwBkAQACAAkJJQtvRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAAALgAECgMJAwAAAA==.',
Re='Rede:BAAALgAECgIJAwAAAA==.Reilu:BAAALgADCgIJAgAAAA==.Rein:BAABLgAECn8tAAIDAAkJXhL1OQAVAgADAAkJXhL1OQAVAgAAAA==.Relieff:BAAALgAECgUJDgAAAA==.Relmin:BAAALgAECgEJAQAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.',
Ri='Rio:BAABLgAECn8wAAIYAAkJWxhKCwA9AgAYAAkJWxhKCwA9AgAAAA==.Ris:BAABLgAECn8oAAIDAAkJKh/PIwBxAgADAAkJKh/PIwBxAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgAECgMJAwAAAA==.Roguesgambit:BAAALgAECgkJCQAAAA==.Roknathar:BAABLgAECn8vAAMmAAkJyCUWAgDEAgAmAAgJwSUWAgDEAgAIAAMJ4R7QfAAWAQAAAA==.Ronburrgandy:BAAALgAECgEJAQAAAA==.Ronilf:BAABLgAECn8lAAIiAAgJ4xlHEgDwAQAiAAgJ4xlHEgDwAQAAAA==.Rono:BAAALgADCggJEwAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8oAAMeAAkJURy8DwA6AgAeAAkJURy8DwA6AgAfAAIJyhN8iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgAECgcJBwAAAA==.Rukaza:BAAALgAECgEJAQABLgAFFAUJCAAZANMUAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Sabrilla:BAAALgAECgEJAgAAAA==.Saerenity:BAAALgAECgMJAwAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgAECgEJAQAAAA==.Sana:BAABLgAECn8vAAIlAAkJ2CAOBgDgAgAlAAkJ2CAOBgDgAgAAAA==.Saphihr:BAAALgADCgYJBgAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAHAAAAAA==.',
Se='Sedo:BAAALgAECgUJCQAAAA==.Selenis:BAAALgAECgQJBgABLgAECgkJLgAVANskAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shamainiac:BAABLgAECn88AAIlAAkJ+RQRGAD4AQAlAAkJ+RQRGAD4AQAAAA==.Shamith:BAAALgAECgEJAQAAAA==.Shaomai:BAACLgAFFH8GAAIlAAMJUhdQIwDhAAAlAAMJUhdQIwDhAAAuAAQKfysAAyUACQn1IP8HALwCACUACQn1IP8HALwCAAIABAkvDRpzAMMAAAEuAAUUBAkIAA0AIw4A.Sharper:BAABLgAECn8XAAIZAAcJaRyyQgCeAQAZAAcJaRyyQgCeAQABLgAFFAMJCgAVANAdAA==.Shep:BAAALgAECgMJAwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shiok:BAAALgAECgMJAwAAAA==.Shishkademon:BAAALgAECgIJAgAAAA==.Shoknorris:BAAALgADCgkJCQAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgQJCQAAAA==.Silverwin:BAABLgAECn8eAAIfAAYJhhHXMQAeAQAfAAYJhhHXMQAeAQAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8lAAIoAAkJRRqrAQBWAgAoAAkJRRqrAQBWAgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJDgAAAA==.Smitted:BAABLgAECn8ZAAMGAAcJ5A5UjgA0AQAGAAcJlwtUjgA0AQANAAYJ3QpXIwDtAAAAAA==.Smitty:BAABLgAECn8VAAMBAAgJnhV7HQCaAQABAAgJeBR7HQCaAQApAAgJQxC6IwBqAQAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAAALgAECgYJDgAAAA==.Sophiaa:BAAALgADCgcJBgAAAA==.Sorn:BAABLgAECn8pAAINAAgJShKGEQB/AQANAAgJShKGEQB/AQAAAA==.',
Sp='Spaarkle:BAAALgAECgYJBwAAAA==.Specialheist:BAAALgAECgkJEwAAAA==.Spectrehawk:BAAALgAECgYJDAABLgAFFAQJDwAEAGMZAA==.Speçtre:BAACLgAFFH8PAAIEAAQJYxlMDQBPAQAEAAQJYxlMDQBPAQAuAAQKfy8AAwQACQkNHTUIAG0CAAQACAk0IDUIAG0CABUAAQn+Bn0pAT0AAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgQJBAAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAABLgAECn8aAAIeAAgJGBYGGwDGAQAeAAgJGBYGGwDGAQAAAA==.Stormglaive:BAABLgAECn8aAAMYAAcJPxU8HQDWAQAYAAcJPxU8HQDWAQAZAAEJUwPt6QAoAAAAAA==.Strikedark:BAAALgAECgEJAQAAAA==.Stupidity:BAABLgAECn8sAAMeAAgJeB4NDwBDAgAeAAgJeB4NDwBDAgAfAAIJhBeaTQB7AAAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn83AAMQAAkJXx/IBgAHAwAQAAkJXx/IBgAHAwApAAYJWBPBJgBTAQAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
Sy='Syranda:BAAALgAFFAEJAQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgADCgUJBQABLgAECgkJNAADALUjAA==.Tarysha:BAABLgAECn8hAAIiAAgJ6wlsHgB3AQAiAAgJ6wlsHgB3AQAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn80AAIcAAkJ5xCKFgBfAQAcAAkJ5xCKFgBfAQAAAA==.Tayoma:BAAALgAECgEJAQAAAA==.Tazara:BAAALgAECgQJBQAAAA==.',
Te='Tealth:BAAALgAECgYJBgAAAA==.Ted:BAABLgAECn8hAAIlAAcJQBZJKAB/AQAlAAcJQBZJKAB/AQAAAA==.Tehgermza:BAAALgADCgMJAwAAAA==.Tehgrimza:BAABLgAECn8lAAMbAAkJVRn1GQBvAgAbAAkJVRn1GQBvAgAgAAEJrxCDdAAwAAAAAA==.Teias:BAAALgAECggJCgABLgAFFAMJCgAfAC4YAA==.Teka:BAAALgADCgMJAwAAAA==.Temu:BAAALgAECgYJCAABLgAECggJHwADAM4iAA==.Tet:BAAALgAFFAIJAgAAAA==.Tevia:BAABLgAECn8tAAIPAAkJ4xgtCgAeAgAPAAkJ4xgtCgAeAgAAAA==.',
Th='Thalip:BAAALgAECgQJBwAAAA==.Thekingheals:BAAALgAECgIJAgABLgAECggJJgApAAsfAA==.Thokmay:BAABLgAECn8lAAIpAAkJyA8WIACEAQApAAkJyA8WIACEAQAAAA==.Thorel:BAAALgAECgQJBAAAAA==.Thornar:BAAALgAECgUJBQAAAA==.Thunden:BAAALgAECgYJBgAAAA==.',
Ti='Tiandrinna:BAABLgAECn8qAAILAAkJKxxqAQBmAgALAAkJKxxqAQBmAgAAAA==.Tightywhitey:BAAALgAECgYJBwAAAA==.Timkaoss:BAABLgAECn8ZAAMMAAYJpRd3UABkAQAMAAYJpRd3UABkAQAJAAMJNQf8aQBLAAAAAA==.Timmyjudge:BAAALgAECgYJCAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAABLgAECn8eAAIKAAYJYgXuLQCmAAAKAAYJYgXuLQCmAAAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgkJFgAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgMJBQABLgAECggJIwACABokAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgAECgMJBgAAAA==.Trixterwolf:BAAALgADCgUJBwAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAACLgAFFH8GAAIDAAMJggd+bwDVAAADAAMJggd+bwDVAAAuAAQKfysAAgMACQm2F803AB0CAAMACQm2F803AB0CAAAA.',
Ty='Tygrassar:BAAALgAECgIJAgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8wAAIfAAkJVh08BgDwAgAfAAkJVh08BgDwAgAAAA==.',
['Tä']='Täd:BAAALgAFFAEJAQAAAA==.',
Va='Vaelenka:BAAALgADCgMJAwAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAABLgAECn8ZAAMFAAgJIQpJEAAoAQAFAAgJ2ghJEAAoAQAVAAYJPAkTrwDsAAAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAABLgAECn8iAAIGAAgJVx4WLgAmAgAGAAgJVx4WLgAmAgAAAA==.Valicous:BAAALgAECgMJAwAAAA==.Valyerian:BAABLgAECn8uAAITAAgJ5hsOFgCcAgATAAgJ5hsOFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgkJHgAEAGMiAA==.Vandevoker:BAAALgAECgQJCAABLgAECgkJHgAEAGMiAA==.Vanserra:BAAALgADCgcJEAAAAA==.Varregory:BAAALgADCgQJBAAAAA==.Vaxas:BAABLgAECn8jAAIGAAgJ1h9/JgBIAgAGAAgJ1h9/JgBIAgAAAA==.Vaxasus:BAAALgAECgEJAQAAAA==.Vaylorian:BAABLgAECn8VAAIcAAYJFyD1DQDIAQAcAAYJFyD1DQDIAQAAAA==.Vaült:BAABLgAECn8vAAMdAAkJmxWvFgAtAgAdAAkJmxWvFgAtAgAGAAMJPwYbEgFzAAAAAA==.',
Ve='Verianna:BAABLgAECn8uAAQVAAkJ2yT4JABOAgAVAAgJZyH4JABOAgAEAAUJCiXZDAAOAgAFAAMJhBqvFQDiAAAAAA==.Vexmorphis:BAAALgAECgIJAQABLgAECgkJHgAGAJwSAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgAECgQJBAAAAA==.',
Vr='Vraknaar:BAAALgADCgQJBAAAAA==.',
Vt='Vtown:BAAALgAECgMJAwAAAA==.',
Wa='Wadumu:BAABLgAECn8sAAMMAAgJywsOaQAYAQAMAAYJVg4OaQAYAQAcAAgJWQurIwDuAAAAAA==.Wagwanmist:BAABLgAECn8tAAIQAAgJtBlXFgAqAgAQAAgJtBlXFgAqAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warvegas:BAAALgAECgQJBgAAAA==.Warwulf:BAAALgAECgQJBAABLgAECggJJQATADwcAA==.Water:BAAALgADCgEJAQAAAA==.',
Wi='Willowy:BAABLgAECn80AAIDAAkJtSN4CQAbAwADAAkJtSN4CQAbAwAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8cAAQCAAUJ4hOvYwD4AAACAAUJ4hOvYwD4AAAlAAQJ6whOZwB8AAAhAAEJngp8LwAxAAAAAA==.',
Xa='Xaerius:BAABLgAECn83AAMTAAkJ8RWgFQAeAgATAAkJ8RWgFQAeAgAPAAEJ6wWTZgApAAAAAA==.Xalatath:BAAALgADCgcJDQAAAA==.Xan:BAABLgAECn8gAAIDAAkJyRf7QgD3AQADAAkJyRf7QgD3AQAAAA==.Xann:BAAALgAECgIJAgAAAA==.Xannen:BAAALgADCgkJCQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAAALgAECgcJCAAAAA==.Xashadin:BAAALgAECgcJBwAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIDAAcJJiNIPQCCAgADAAcJJiNIPQCCAgAAAA==.',
Xo='Xog:BAAALgAECgIJAgAAAA==.',
Ya='Yarman:BAABLgAECn8eAAIBAAYJTxOpLgAsAQABAAYJTxOpLgAsAQAAAA==.',
Ye='Yeaforpie:BAABLgAECn8bAAMbAAcJiQ9wfQApAQAbAAYJbRFwfQApAQAnAAQJwgsGHACgAAAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAABLgAECn8YAAIdAAgJ7BQEJQC4AQAdAAgJ7BQEJQC4AQAAAA==.',
Yo='Yoshial:BAAALgAECgUJCQAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAABLgAECn81AAMeAAkJThZNEwARAgAeAAkJThZNEwARAgAUAAYJPA1DNQAQAQAAAA==.',
Ze='Zealins:BAAALgADCgUJCAAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQABLgAFFAMJCQAGAMYgAA==.Ziv:BAACLgAFFH8FAAIMAAMJ+BX4LQDaAAAMAAMJ+BX4LQDaAAAuAAQKfzUAAgwACQkqIOoGAC4DAAwACQkqIOoGAC4DAAEuAAUUAwkGABoAYh8A.Ziyn:BAACLgAFFH8GAAIaAAMJYh9TEgAaAQAaAAMJYh9TEgAaAQAuAAQKfxcAAxoACQk+HlwFALkCABoACQk+HlwFALkCAAgABgmuGo5kAE0BAAAA.',
Zo='Zoda:BAAALgAECgEJAQAAAA==.',
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
