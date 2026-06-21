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

local lookup = {'Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Rogue-Assassination','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Warrior-Arms','Mage-Fire','Druid-Restoration','Paladin-Protection','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Unholy','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Warlock-Demonology','Druid-Guardian','Paladin-Holy','Warlock-Destruction','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Evoker-Preservation','Warlock-Affliction','Mage-Arcane','Monk-Windwalker',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aarztok:BAAALgAECgUJBQABLgAFFAcJFgABAOwZAA==.',
Ac='Achepir:BAAALgADCgIJAgAAAA==.Achiella:BAAALgAECgEJAQAAAA==.',
Ad='Advisor:BAACLgAFFH8KAAICAAQJkRBZQADjAAACAAQJkRBZQADjAAAuAAQKfzQAAwIACQmcJG0JAOECAAIACQmcJG0JAOECAAMAAQl5F3KZAEQAAAAA.',
Ae='Aería:BAAALgAECgYJDwAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgAECgEJAQAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgAECgEJAQAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aldoraine:BAAALgAECgEJAgABLgAECgEJAgAEAAAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Altrix:BAAALgAECgUJBgABLgAFFAMJBQAFABkDAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgADCgcJEAAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgAECgQJCAAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Andolas:BAAALgADCgYJCQAAAA==.Angelicuss:BAAALgAECgUJBgABLgAECgkJQgAGAL8jAA==.Annya:BAAALgAECgcJBwAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aparajita:BAAALgAECgEJAwABLgABCgMJAwAEAAAAAA==.Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCwAAAA==.Aristoleh:BAAALgAECgEJAQABLgAFFAcJFAADANgOAA==.Arkahera:BAAALgAECgQJBQABLgAFFAcJFgABAOwZAA==.Arolder:BAABLgAECn8mAAMHAAkJqyGDBgC4AgAHAAkJdSGDBgC4AgAIAAcJZB3dAwA6AgAAAA==.Arredin:BAAALgADCgYJBgAAAA==.Arturium:BAAALgADCgYJCwAAAA==.',
As='Astayuno:BAAALgAECgQJBAAAAA==.',
At='Atabey:BAABLgAECn87AAIJAAkJICIuEQDeAgAJAAkJICIuEQDeAgABLgABCgMJAwAEAAAAAA==.Atimusk:BAAALgADCggJDwABLgAECgYJCgAEAAAAAA==.Atoadaso:BAAALgAECggJEgAAAA==.Attretes:BAAALgADCgcJDwAAAA==.',
Az='Azazél:BAAALgAECgEJAQABLgAFFAQJDQAGACwLAA==.Azcowboy:BAAALgAECgUJEAAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgAECgYJCAAAAA==.',
Ba='Badco:BAAALgAECgQJBAAAAA==.Balacheck:BAABLgAECn8hAAIKAAgJ9QU2CACFAAAKAAgJ9QU2CACFAAAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgAECgEJAQAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAABLgAECn8sAAILAAkJbxxdDACQAgALAAkJbxxdDACQAgAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgYJFAAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAAGAKAcAA==.',
Bi='Bigbadwoof:BAAALgAECgEJAgAAAA==.Bighog:BAACLgAFFH8UAAIMAAQJGyHRDQBRAQAMAAQJGyHRDQBRAQAuAAQKfxgAAwwABwloJmwHAI0CAAwABwloJmwHAI0CAA0AAgkZFBxUAIUAAAAA.Bipbipbup:BAAALgAECgEJAQAAAA==.',
Bj='Björn:BAAALgADCgcJBwAAAA==.',
Bl='Blaazzin:BAAALgADCgcJHgAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Blinck:BAAALgAECgUJBQAAAA==.Blinkz:BAAALgAECgUJBQAAAA==.Bloomzy:BAACLgAFFH8KAAIGAAMJFiH4DACrAAAGAAMJFiH4DACrAAAuAAQKfy4AAwYACQluGoo1AEMCAAYACQluGoo1AEMCAA4AAgl6G1oKAJ8AAAAA.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAABLgAFFH8FAAIFAAMJGQM/CQC1AAAFAAMJGQM/CQC1AAAAAA==.Boombástic:BAABLgAECn8oAAMLAAkJaQ8pLQBwAQALAAgJMhApLQBwAQAPAAIJ0A/gpgBlAAAAAA==.Boomco:BAABLgAECn8dAAIKAAgJOBGSUwCoAQAKAAgJOBGSUwCoAQAAAA==.Boomtothekin:BAAALgAECgIJAgABLgAFFAMJCwAJALQTAA==.Bootes:BAAALgAECgMJAwAAAA==.Bors:BAAALgADCgUJEAAAAA==.Boulderholdr:BAAALgAECgYJEQAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Bravillius:BAAALgADCgkJDgAAAA==.Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAABLgAECn8UAAIQAAgJNg00JADzAAAQAAgJNg00JADzAAAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAIQAAkJyRmeCgAkAgAQAAkJyRmeCgAkAgAAAA==.Bryda:BAAALgAECgQJCgAAAA==.',
Bu='Bubblez:BAAALgAECgYJBwAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAABLgAECn8WAAIBAAYJbA2uUAC/AAABAAYJbA2uUAC/AAAAAA==.',
Ca='Cajbo:BAABLgAECn89AAIFAAkJViHdAQDbAgAFAAkJViHdAQDbAgAAAA==.Calyssa:BAABLgAECn8eAAIJAAgJ6w5BjQBXAQAJAAgJ6w5BjQBXAQAAAA==.Candyflöss:BAACLgAFFH8JAAIMAAQJbBxCEwALAQAMAAQJbBxCEwALAQAuAAQKfyAAAwwABgkuJMYOAP8BAAwABgkuJMYOAP8BAA0AAQkLEEZ5ADAAAAAA.Capmkrunch:BAAALgAECgEJAwABLgAECggJEgAEAAAAAA==.Caraling:BAAALgADCgYJBwAAAA==.Caralynn:BAAALgAECgUJDQAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAACLgAFFH8HAAIRAAQJJhTaLwD3AAARAAQJJhTaLwD3AAAuAAQKf0QAAhEACQkbIdMFAEoDABEACQkbIdMFAEoDAAAA.Castisteus:BAAALgAECgYJCAAAAA==.Cathelina:BAAALgADCggJFQAAAA==.Cathom:BAAALgAECgUJCgAAAA==.',
Ch='Charcasm:BAAALgAECgYJCAAAAA==.Charizaard:BAAALgAECgYJCQAAAA==.Charizaardx:BAACLgAFFH8SAAMSAAYJFgqEAAC7AAATAAUJqwPUNQDsAAASAAQJGw+EAAC7AAAuAAQKf0kAAxIACQl4GjMEADgCABIACQmSGTMEADgCABMACAnRFPYlAI0BAAAA.Chevytron:BAAALgAECgYJEwAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8dAAMMAAgJEg8QAgB2AAAUAAYJYQ9zXgDaAAAMAAQJiQsQAgB2AAAAAA==.Clives:BAAALgAECgEJAQAAAA==.Clmx:BAAALgADCgIJAgAAAA==.Clément:BAAALgADCgUJBgAAAA==.',
Co='Coffeebeans:BAABLgAECn8iAAMPAAgJExbjPgCnAQAPAAcJfxTjPgCnAQALAAgJwAt6NgA8AQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowdeath:BAAALgAECgEJAQAAAA==.Cowkiller:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgYJDgAAAA==.Creslan:BAAALgAECgYJBgABLgAECgkJVQAVACsfAA==.Crimsonthot:BAAALgAECggJDQAAAA==.Crogan:BAABLgAECn8UAAQWAAkJzAgJNgApAQAWAAgJJwkJNgApAQAXAAUJJAh+XAClAAAYAAEJ+gVAWgAuAAAAAA==.Crysiscane:BAAALgADCgYJBQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQABLgAECggJEgAEAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgAECgYJBwAAAA==.Dagul:BAAALgAECgcJCwAAAA==.Dalna:BAABLgAECn86AAIRAAkJTBnKEgCHAgARAAkJTBnKEgCHAgAAAA==.Danilex:BAABLgAECn8cAAIGAAgJCx9pSABeAgAGAAgJCx9pSABeAgABLgAFFAgJMwAYAMEbAA==.Danksoul:BAAALgAECgkJAQABLgAECgYJAwAEAAAAAA==.Darat:BAAALgADCgEJAQAAAA==.Darcorin:BAABLgAECn8fAAIZAAgJIBbfcACDAQAZAAgJIBbfcACDAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAABLgAECn8aAAIKAAgJkgeqlQAVAQAKAAgJkgeqlQAVAQAAAA==.Darksaber:BAABLgAECn8UAAILAAUJlQs2WgCqAAALAAUJlQs2WgCqAAAAAA==.Dasthodan:BAAALgAECgUJCAAAAA==.Dayne:BAAALgAECgcJDQAAAA==.',
Dc='Dctrpepper:BAAALgAECgIJAgAAAA==.',
De='Deathcore:BAAALgADCgkJEwAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathtardza:BAAALgAECgQJBwAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8xAAQLAAkJJQQKRgD0AAALAAkJJQQKRgD0AAAPAAkJHAYYbQDtAAAaAAIJhQCIOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Delvisprezly:BAAALgAECggJEgAAAA==.Demonica:BAABLgAECn8pAAQbAAkJ+whZEgApAQAbAAkJ4wdZEgApAQAcAAUJ4gYqRADmAAAdAAIJwwxe8QBdAAAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Denastus:BAAALgAECgUJBQAAAA==.Dethknyght:BAAALgAECgkJCgABLgAFFAcJFgABAOwZAA==.Detoxin:BAAALgAECgIJAgAAAA==.Devick:BAAALgAECgEJAQAAAA==.',
Di='Dinta:BAABLgAECn9TAAIJAAkJjxxFHACbAgAJAAkJjxxFHACbAgAAAA==.Dionysys:BAAALgAECgEJAgABLgABCgMJAwAEAAAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAABLgAECn8dAAIKAAgJLRt+KwAvAgAKAAgJLRt+KwAvAgAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgAECgMJAwAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8fAAIBAAkJLhXzFgDyAQABAAkJLhXzFgDyAQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8sAAIeAAkJTg0qGgDOAQAeAAkJTg0qGgDOAQAAAA==.Dummblond:BAACLgAFFH8QAAMPAAQJfAcrPQC7AAAPAAQJfAcrPQC7AAALAAIJMwU/RQBiAAAuAAQKfx4AAw8ACAlrEYU7AKYBAA8ACAlrEYU7AKYBAAsABwkxCGxZAL4AAAAA.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAABLgAECn8XAAIfAAcJKB0tUgClAQAfAAcJKB0tUgClAQAAAA==.',
Dy='Dyonesa:BAAALgAECgUJBQAAAA==.Dysfunction:BAABLgAECn8XAAIgAAkJeRBfHgBaAQAgAAkJeRBfHgBaAQAAAA==.',
Ea='Earthshield:BAAALgAECgcJDgABLgAECgkJPwAhADckAA==.',
Eg='Ego:BAABLgAECn8iAAIhAAkJPyLYBQAyAwAhAAkJPyLYBQAyAwAAAA==.',
El='Elipto:BAAALgAECgYJBgAAAA==.Ellaana:BAAALgAECgUJEAAAAA==.Elotarra:BAAALgAECgEJAQAAAA==.Elowentinsel:BAAALgAECgEJAQAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgAECgMJAwAAAA==.',
En='Enduran:BAAALgAECgYJDQAAAA==.',
Er='Erasi:BAABLgAECn8zAAMXAAkJVApVLQBtAQAXAAkJVApVLQBtAQAWAAUJzwJUXgBhAAAAAA==.',
Es='Es:BAABLgAECn8UAAIZAAcJ8wTGpgA0AQAZAAcJ8wTGpgA0AQAAAA==.Escanorlion:BAAALgADCgcJBwAAAA==.Esileda:BAAALgAECgQJBAAAAA==.Esttsumi:BAAALgAECgkJDwAAAA==.',
Eu='Euphia:BAAALgAECgUJDAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8uAAIKAAkJzxBaBAD0AAAKAAkJzxBaBAD0AAAAAA==.Exodiá:BAAALgAECgYJCwAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8uAAIJAAkJVB1ZIQCBAgAJAAkJVB1ZIQCBAgAAAA==.Faethe:BAAALgAECgEJAgABLgAECgkJQgAGAL8jAA==.Faithfulpain:BAAALgADCgYJBgAAAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farmerpolly:BAAALgADCgYJCQAAAA==.Farwolf:BAABLgAECn8oAAIKAAgJWAoZdgBTAQAKAAgJWAoZdgBTAQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECggJBwABLgAFFAMJCAAZAGgXAA==.Fee:BAACLgAFFH8hAAIJAAYJSR9hAQCsAQAJAAYJSR9hAQCsAQAuAAQKfz4AAgkACQkUJVYIACgDAAkACQkUJVYIACgDAAAA.Fellyn:BAAALgAECgQJBQAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgAECgMJAwAAAA==.Festerr:BAAALgADCgQJAQAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.Fishstick:BAAALgAECgkJDQAAAA==.',
Fl='Flameheart:BAABLgAECn8cAAMiAAgJqQqFEwAVAQAiAAgJqQqFEwAVAQAfAAEJAALtaAEPAAAAAA==.Fleathulhu:BAACLgAFFH8OAAIWAAMJAhdyAgCdAAAWAAMJAhdyAgCdAAAuAAQKfzQAAhYACQn0HV4HAPkCABYACQn0HV4HAPkCAAAA.Flungpu:BAAALgADCgkJFwABLgAECgkJNgAKANsSAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAABLgAECn8nAAMfAAgJqxDmYQB7AQAfAAgJqxDmYQB7AQAiAAEJvRI0PgA0AAAAAA==.Foxieshoxie:BAAALgAECgEJAwAAAA==.Foxylocksy:BAAALgADCgkJCgAAAA==.',
Fr='Frontierland:BAAALgADCgcJDQAAAA==.Frostdoom:BAAALgADCgYJCAAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgADCggJCAAAAA==.',
Fu='Furgy:BAAALgAECgEJAQAAAA==.Furrfoxsake:BAAALgAECgQJBwABLgAECggJDwAeAJcbAA==.Fuzball:BAAALgADCgEJAQAAAA==.Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Galfure:BAAALgADCgYJBgAAAA==.Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAEAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn83AAIFAAkJhRZmBgACAgAFAAkJhRZmBgACAgAAAA==.',
Ge='Genovefa:BAAALgAECgIJAgAAAA==.',
Gh='Ghoulmaxing:BAABLgAFFH8IAAIZAAMJaBfsCADoAAAZAAMJaBfsCADoAAAAAA==.Ghøulish:BAAALgAECgUJBwABLgAECggJMQAPAFwMAA==.',
Gi='Gimper:BAAALgADCgcJFwAAAA==.',
Gl='Glaistia:BAAALgAECgEJAQAAAA==.Glen:BAAALgAECgUJEAAAAA==.Glowstik:BAAALgAECgQJBAAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.Gormlaîth:BAAALgAECgQJBwABLgAECgYJCgAEAAAAAA==.',
Gr='Grabmymelonz:BAAALgAECgUJBQAAAA==.Graeman:BAAALgADCgMJAwAAAA==.Grandpaslay:BAAALgAECgQJCQAAAA==.Greatpàw:BAAALgAECgEJAQAAAA==.Grisly:BAAALgADCgUJBQAAAA==.',
Gu='Gurrney:BAAALgADCgYJBgAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgAECgYJEQAAAA==.Habbypallie:BAAALgADCgYJFAAAAA==.Haimanist:BAABLgAECn8ZAAIQAAgJliAlAwDwAgAQAAgJliAlAwDwAgABLgAFFAcJFgABAOwZAA==.Halixan:BAABLgAECn8gAAIjAAkJWyPyAgDiAgAjAAkJWyPyAgDiAgAAAA==.Handlebardoc:BAACLgAFFH8OAAIZAAQJnxgXZwAqAQAZAAQJnxgXZwAqAQAuAAQKf0AAAhkACQleIoASANoCABkACQleIoASANoCAAAA.Harmoni:BAAALgAECgQJBQABLgAECgkJQgAGAL8jAA==.Hatorade:BAAALgAECgUJBQAAAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgAECgkJBQAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgkJEQAAAA==.',
Ho='Holyname:BAAALgAECgQJAwAAAA==.Holysim:BAAALgAECgEJAQAAAA==.Honir:BAAALgAECgYJBgAAAA==.',
Hu='Hunteð:BAAALgAECgEJAgAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgAECgIJAgAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8yAAMiAAkJHwwsFgD2AAAfAAkJ0AjLcQBWAQAiAAYJGw4sFgD2AAAAAA==.',
Ir='Ireus:BAAALgAECgIJAgAAAA==.Ironfizt:BAAALgAECggJDwABLgAECgkJKAAkAIgYAA==.',
Is='Islet:BAAALgAECgEJAQAAAA==.Istia:BAAALgADCgUJBQAAAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.',
Iu='Iudex:BAAALgAECggJDwAAAA==.Iutu:BAAALgAECgUJBQAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAABLgAECn8/AAMhAAkJNyRFAgBYAwAhAAkJNyRFAgBYAwAJAAgJRQ+fhABmAQAAAA==.Jarvy:BAAALgAECggJCAAAAA==.',
Je='Jedavon:BAAALgAECgEJAQAAAA==.Jenhadin:BAAALgAECgcJCwAAAA==.Jerreden:BAAALgADCgYJBgAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.Jestic:BAABLgAECn8nAAIkAAkJ6hNyAAC1AQAkAAkJ6hNyAAC1AQAAAA==.',
Ji='Jiangshi:BAAALgAECgYJCgAAAA==.Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ju='Justpwnedu:BAAALgAECgkJCgAAAA==.',
Ka='Kaazel:BAABLgAECn82AAIKAAkJ2xJROAD9AQAKAAkJ2xJROAD9AQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgYJEgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgAECggJDQAAAA==.Kamsham:BAAALgAECgQJBQABLgAECgkJIwABAJ8VAA==.Kandiquake:BAAALgAECgIJAgAAAA==.Karea:BAAALgAECgcJDgAAAA==.Karite:BAABLgAECn80AAIlAAkJ/iKCAQDgAgAlAAkJ/iKCAQDgAgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAIRAAgJRxnJHgAjAgARAAgJRxnJHgAjAgAAAA==.Karveila:BAAALgAECgQJBAAAAA==.Katyla:BAAALgADCgQJBAABLgAECgkJMwAKAOoMAA==.Kazar:BAAALgADCgcJDwAAAA==.Kazenoth:BAABLgAECn8rAAMTAAkJxxreFwAYAgATAAkJxxreFwAYAgAmAAEJbxFuPAAyAAAAAA==.',
Ke='Kellement:BAAALgAECgUJBQAAAA==.Ken:BAABLgAECn8bAAILAAgJVBbWHADiAQALAAgJVBbWHADiAQABLgAECgkJRQAfAHEaAA==.Kennychaoss:BAABLgAECn8wAAMCAAkJzR2iDQDpAgACAAkJzR2iDQDpAgADAAcJZw33RwAUAQAAAA==.Kennykaos:BAAALgAECgQJBwAAAA==.',
Kh='Khrisbkreme:BAAALgAECgEJAQABLgAECggJEgAEAAAAAA==.',
Ki='Kille:BAABLgAECn8eAAIKAAgJxhd3OAD8AQAKAAgJxhd3OAD8AQAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Kobebrÿant:BAAALgAECgYJDAAAAA==.Kobeqt:BAAALgAECgYJCQAAAA==.Koland:BAAALgADCgkJGAAAAA==.Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn84AAILAAkJXA4eJwCVAQALAAkJXA4eJwCVAQAAAA==.Kostazu:BAABLgAECn9WAAIDAAkJuhKDIgDQAQADAAkJuhKDIgDQAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAFFAYJIQAJAEkfAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAFFAMJDgAWAAIXAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAgABLgAECgMJBgAEAAAAAA==.',
La='Laity:BAABLgAECn9OAAIJAAkJEyGmCgARAwAJAAkJEyGmCgARAwAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Laraithe:BAAALgADCgEJAQAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgAECgEJAQAAAA==.Lazraar:BAAALgAECgEJAQAAAA==.Lazylaz:BAABLgAECn8vAAIaAAkJNyQ5AgAKAwAaAAkJNyQ5AgAKAwABLgAFFAgJIgAZAAEeAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAABLgAECn86AAIjAAgJhCK2AwDDAgAjAAgJhCK2AwDDAgAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJCQAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAABLgAECn8pAAMcAAgJ6BXbIgBhAQAcAAYJUxjbIgBhAQAdAAgJlwwZbABMAQAAAA==.Lifebloom:BAAALgAECgIJAgABLgAECgkJPwAhADckAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAFFAMJCAAeACMhAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8zAAIKAAkJ6gyNVACmAQAKAAkJ6gyNVACmAQAAAA==.Livedcargox:BAAALgAECgYJBgAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Loqir:BAAALgAFFAIJAwABLgAFFAcJHAATAE8aAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgAECgEJAQAAAA==.',
Ly='Lycanbyte:BAAALgAECgYJEQAAAA==.Lylith:BAABLgAECn82AAMcAAkJLBdQEgAIAgAcAAkJLBdQEgAIAgAdAAQJawXQ7QBiAAAAAA==.Lyphiandraa:BAAALgAECgEJAQAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJBwAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Maddicollins:BAAALgAECgYJDAABLgAECgkJLAAWACwdAA==.Magdalena:BAABLgAECn8+AAIKAAkJ1w/LAgBHAQAKAAkJ1w/LAgBHAQAAAA==.Magehawk:BAAALgAECgUJBQAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magmaface:BAAALgAECgcJCAAAAA==.Magnólia:BAABLgAECn8tAAICAAkJsyLsCAAjAwACAAkJsyLsCAAjAwAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Maithre:BAAALgAECgIJAwAAAA==.Makima:BAAALgADCgcJCQABLgAFFAQJDQAfAFcXAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Manxgina:BAAALgAECgQJBwABLgAFFAUJEgATAKIRAA==.Maribelle:BAAALgAECggJDAABLgAECgkJQgAGAL8jAA==.Marrent:BAAALgADCgcJGQAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJDAAAAA==.Mazeltov:BAABLgAECn8WAAIMAAgJPRrNDgAcAgAMAAgJPRrNDgAcAgAAAA==.',
Me='Melomel:BAABLgAECn8oAAIjAAgJOxO+EQCZAQAjAAgJOxO+EQCZAQAAAA==.Melonsquezer:BAABLgAECn83AAMQAAkJsh7eBQCOAgAQAAkJsh7eBQCOAgAJAAEJ2RPeMwE9AAAAAA==.Menmei:BAABLgAECn8tAAIKAAgJwRUGRQDTAQAKAAgJwRUGRQDTAQAAAA==.Mexicanrage:BAAALgADCgQJBAAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgAECgUJEAAAAA==.Minien:BAABLgAECn82AAMjAAkJdB2dCwD7AQAjAAgJIR2dCwD7AQADAAgJeRjlIwDHAQAAAA==.Minko:BAABLgAECn8rAAIKAAkJIhsyIABmAgAKAAkJIhsyIABmAgAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAFFAQJDQAGACwLAA==.',
Mo='Modelo:BAAALgAFFAEJAQAAAA==.Molulu:BAAALgADCgcJCwABLgAECgYJIAAGAC8IAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn9VAAIVAAkJKx+mAgC/AgAVAAkJKx+mAgC/AgAAAA==.Morillic:BAABLgAECn8YAAQnAAcJqxhwCwCmAQAnAAcJqxhwCwCmAQAiAAMJrA0MSACWAAAfAAIJMxSCCgFIAAABLgAECggJGgAXABgWAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgAECgEJAQAAAA==.',
Ms='Mstrcrowly:BAABLgAECn8wAAMfAAgJqiBtFgCdAgAfAAgJqiBtFgCdAgAnAAIJvhwqOgBAAAAAAA==.',
Mu='Mustachjones:BAABLgAECn81AAIfAAkJERxUIABjAgAfAAkJERxUIABjAgAAAA==.',
My='Myros:BAABLgAECn86AAMGAAkJfBbhQwAQAgAGAAkJfBbhQwAQAgAOAAEJ8gWqFQApAAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Nadiaa:BAAALgADCgYJBgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgAECgcJDAAAAA==.Narestor:BAABLgAECn8YAAIUAAgJHRPBMQDlAQAUAAgJHRPBMQDlAQABLgAFFAYJFQATAOEKAA==.Nasril:BAAALgAECggJEgAAAA==.Nazervis:BAAALgAECgUJBQABLgAFFAgJIgAZAAEeAA==.Nazurend:BAABLgAECn8pAAMGAAkJJRRYRgAIAgAGAAkJJRRYRgAIAgAOAAEJ9QUhFgAmAAAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAFFAEJAgAAAA==.Nemesîs:BAAALgADCgkJGwAAAA==.Nero:BAABLgAECn8nAAIcAAkJTyFXCACoAgAcAAkJTyFXCACoAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMfAAgJNAUjfQBhAQAfAAgJNAUjfQBhAQAiAAIJywFjZgBDAAAAAA==.Nimuerose:BAAALgAECgEJAQAAAA==.',
No='Nortree:BAABLgAECn8qAAIPAAgJyxJrOwCmAQAPAAgJyxJrOwCmAQAAAA==.Nost:BAABLgAECn8sAAIJAAgJDhyRQAAFAgAJAAgJDhyRQAAFAgAAAA==.Notalock:BAAALgADCgIJAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.Novena:BAAALgAECgQJBAABLgAECgkJLQACALMiAA==.',
Nu='Nulwyrm:BAABLgAECn8rAAMTAAkJQBuBEABjAgATAAkJQBuBEABjAgASAAEJohhQIQBKAAAAAA==.Numira:BAAALgADCgMJAwAAAA==.',
Ny='Nymue:BAAALgAECgMJAwAAAA==.Nyyrivik:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8tAAICAAgJRR+qGACEAgACAAgJRR+qGACEAgAAAA==.',
Oh='Ohitsadragon:BAACLgAFFH8FAAISAAIJrwpGCgCCAAASAAIJrwpGCgCCAAAuAAQKfyAAAhIACAkMFSEIALEBABIACAkMFSEIALEBAAAA.',
On='Ono:BAAALgAECgEJAQAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAEAAAAAA==.Oreoscruunit:BAAALgAECgEJAgABLgAECggJEgAEAAAAAA==.',
Ow='Owl:BAABLgAECn8fAAInAAkJAwxUDQBgAQAnAAkJAwxUDQBgAQAAAA==.Owlcatraz:BAACLgAFFH8OAAIPAAUJgwcOLwD2AAAPAAUJgwcOLwD2AAAuAAQKfxUAAwsACAlXGvwZAPwBAAsACAlXGvwZAPwBAA8ABQknC5V3AM8AAAAA.',
Pa='Paendrag:BAAALgAECgUJBQAAAA==.Paladinna:BAAALgADCgMJAwAAAA==.Panadarama:BAACLgAFFH8WAAIBAAcJ7BmACgDqAQABAAcJ7BmACgDqAQAuAAQKfygAAgEACAkWJWgEAEUDAAEACAkWJWgEAEUDAAAA.Pandmei:BAAALgADCgkJCQAAAA==.Panteragon:BAABLgAECn8rAAIeAAgJgAi/AQCiAAAeAAgJgAi/AQCiAAAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAABLgAECn8lAAIKAAgJaQrRbgBjAQAKAAgJaQrRbgBjAQAAAA==.',
Pe='Peachyboy:BAAALgADCgMJAwAAAA==.Periwinkle:BAABLgAECn8eAAIWAAgJZg/NKACAAQAWAAgJZg/NKACAAQAAAA==.Persaud:BAACLgAFFH8UAAMnAAUJrRmCCADxAAAfAAUJLxeiSwAwAQAnAAMJwRWCCADxAAAuAAQKfxwAAyIACQkkGtsPANEBACIABwmeEtsPANEBAB8ABQn0Hm1RAKcBAAAA.',
Ph='Phidra:BAABLgAECn9FAAMCAAkJIw/7OwC/AQACAAkJIw/7OwC/AQADAAQJTga/agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgAECgYJIAAGAC8IAA==.Phranky:BAAALgAECgEJBAABLgAECggJEgAEAAAAAA==.Phytos:BAAALgAECgEJAQAAAA==.',
Pi='Pixiebrew:BAAALgAECgUJDgAAAA==.Pizzagirl:BAAALgAECgYJDAAAAA==.',
Pl='Plutrax:BAAALgAECgYJEAAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.',
Pr='Predatorc:BAABLgAECn8dAAIKAAkJaArHTgB9AQAKAAkJaArHTgB9AQAAAA==.Prepotêntê:BAAALgAECgYJCgAAAA==.Primevil:BAABLgAECn8WAAIJAAcJqBTLdgCAAQAJAAcJqBTLdgCAAQAAAA==.Primevl:BAABLgAECn8VAAIaAAgJmxR2AABNAQAaAAgJmxR2AABNAQAAAA==.Primévil:BAABLgAECn80AAIdAAkJ4Aw1WQB8AQAdAAkJ4Aw1WQB8AQAAAA==.',
Pu='Puma:BAABLgAECn8VAAQPAAYJjgKksQBWAAAPAAYJjgKksQBWAAALAAMJjwEQdwBHAAAgAAIJ0gGGjAASAAAAAA==.',
Py='Pyrissa:BAAALgADCgEJAQAAAA==.',
['Pí']='Píp:BAAALgADCggJDQAAAA==.',
Qu='Quarz:BAAALgAECgMJBAAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.Quoternion:BAAALgAECgEJAQABLgAFFAQJBwARACYUAA==.',
Ra='Raden:BAAALgADCgYJCgAAAA==.Raediant:BAAALgAECgUJBwABLgAECgkJHwABAC4VAA==.Raelek:BAAALgAECgQJBAAAAA==.Ragethecage:BAAALgAECgEJAQAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Ragsonfire:BAAALgADCgIJAgAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8lAAMUAAgJPBygHQABAgAUAAgJPBygHQABAgAMAAcJrRS7HgA9AQAAAA==.Raquel:BAABLgAECn8jAAICAAkJJQtvRwBkAQACAAkJJQtvRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAABLgAECn8PAAIeAAgJlxs/DQBSAgAeAAgJlxs/DQBSAgAAAA==.',
Re='Rede:BAAALgAECgIJAwAAAA==.Reeyou:BAAALgAECggJEQABLgAECgkJRQAfAHEaAA==.Reign:BAACLgAFFH8NAAIGAAQJLAt8BgAfAQAGAAQJLAt8BgAfAQAuAAQKf0kAAgYACQngGcokAIkCAAYACQngGcokAIkCAAAA.Reilu:BAAALgADCgIJAgAAAA==.Relieff:BAAALgAECgYJEwAAAA==.Relmin:BAAALgAECgEJAQAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.Revival:BAAALgAECgYJBwABLgAECgkJPwAhADckAA==.',
Ri='Rio:BAABLgAECn9HAAIcAAkJSh8+BgDUAgAcAAkJSh8+BgDUAgAAAA==.Ris:BAABLgAECn84AAIGAAkJtB/xGADEAgAGAAkJtB/xGADEAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgAECgMJAwAAAA==.Rockyrogue:BAABLgAECn8eAAIkAAgJDQepAgB0AAAkAAgJDQepAgB0AAAAAA==.Roknathar:BAABLgAECn8xAAMVAAkJyCXRAgC3AgAVAAgJwSXRAgC3AgAKAAMJ4R4UmgANAQAAAA==.Rolldemort:BAAALgAECgIJAwAAAA==.Ronburrgandy:BAAALgAECgEJAQAAAA==.Ronilf:BAABLgAECn8oAAIkAAkJiBjGFwDcAQAkAAkJiBjGFwDcAQAAAA==.Rono:BAAALgADCggJEwAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8oAAMXAAkJURxpFAAqAgAXAAkJURxpFAAqAgAWAAIJyhN8iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgAECgcJCAAAAA==.Rukaza:BAAALgAECgEJAQABLgAFFAUJEwAdAEwdAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Sabrilla:BAAALgAECgQJAwAAAA==.Saerenity:BAAALgAECgMJAwAAAA==.Sahala:BAAALgADCgEJAQAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgAECgEJAQAAAA==.Saphihr:BAAALgADCgYJBgAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAEAAAAAA==.',
Se='Sedo:BAABLgAECn8UAAIGAAYJbAPi/wCtAAAGAAYJbAPi/wCtAAAAAA==.Selenis:BAAALgAECgcJDQABLgAECgkJNwAHAJolAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowmonarc:BAAALgAECgYJCwAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shamainiac:BAABLgAECn9IAAIDAAkJpRmMEwBQAgADAAkJpRmMEwBQAgAAAA==.Shamith:BAAALgAECgcJDgAAAA==.Shammymax:BAAALgADCgkJAQAAAA==.Shaomai:BAACLgAFFH8LAAIDAAQJyhdhJAAHAQADAAQJyhdhJAAHAQAuAAQKfysAAwMACQn1IAYLALECAAMACQn1IAYLALECAAIABAkvDRpzAMMAAAAA.Sharper:BAACLgAFFH8KAAIdAAQJ4xpPOgA8AQAdAAQJ4xpPOgA8AQAuAAQKfxcAAh0ABwlpHG9OAJoBAB0ABwlpHG9OAJoBAAEuAAUUBAkOABkAnxgA.Shep:BAAALgAECgMJAwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shi:BAAALgAECgQJBAAAAA==.Shifte:BAAALgAECggJEwAAAA==.Shingwauk:BAAALgADCgMJAwAAAA==.Shiok:BAAALgAECgMJAwAAAA==.Shishkademon:BAAALgAECgIJAgAAAA==.Shocks:BAAALgAECgYJBgABLgAFFAYJIQAJAEkfAA==.Shoknorris:BAAALgADCgkJCQAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgcJDAAAAA==.Silverwin:BAABLgAECn8tAAIWAAgJhA/OLQBeAQAWAAgJhA/OLQBeAQAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8lAAIoAAkJRRpZAgA5AgAoAAkJRRpZAgA5AgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJDgAAAA==.Smitted:BAABLgAECn8ZAAMJAAcJ5A61sgAbAQAJAAcJlwu1sgAbAQAQAAYJ3QpXIwDtAAAAAA==.Smitty:BAABLgAECn8XAAMBAAgJnhWiIgCUAQABAAgJeBSiIgCUAQApAAgJQxD2LABZAQAAAA==.',
Sn='Snakmag:BAAALgAECgEJAQAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAABLgAECn8bAAMJAAYJMQ5/ygD6AAAJAAYJMQ5/ygD6AAAhAAYJWBQYAgDCAAAAAA==.Sophiaa:BAAALgADCgcJBgAAAA==.Sorn:BAABLgAECn80AAIQAAkJRBECEQC0AQAQAAkJRBECEQC0AQAAAA==.',
Sp='Spaarkle:BAAALgAECggJDwAAAA==.Specialheist:BAABLgAECn8bAAIWAAkJ1QKsSgC5AAAWAAkJ1QKsSgC5AAAAAA==.Spectrehawk:BAAALgAFFAMJAwABLgAFFAQJFgAHANQjAA==.Speçtre:BAACLgAFFH8WAAIHAAQJ1CMZDgCdAQAHAAQJ1CMZDgCdAQAuAAQKfy8AAwcACQkNHU4LAFsCAAcACAk0IE4LAFsCABkAAQn+BilmAT0AAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgQJBAAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAABLgAECn8aAAIXAAgJGBaAIQC6AQAXAAgJGBaAIQC6AQAAAA==.Stormglaive:BAABLgAECn8aAAMcAAcJPxU8HQDWAQAcAAcJPxU8HQDWAQAdAAEJUwPt6QAoAAAAAA==.Strikedark:BAAALgAECgEJAQAAAA==.Stupidity:BAABLgAECn8sAAMXAAgJeB43EwA4AgAXAAgJeB43EwA4AgAWAAIJhBe0WAB3AAAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn9HAAMRAAkJ3x/4BwAdAwARAAkJ3x/4BwAdAwApAAgJRhTGIQChAQAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
Sy='Synterra:BAAALgADCgkJCQAAAA==.Syranda:BAAALgAFFAEJAQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgAECgIJAwABLgAECgkJQgAGAL8jAA==.Tarysha:BAABLgAECn8qAAIkAAkJvwlnHQCrAQAkAAkJvwlnHQCrAQAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn80AAIgAAkJ5xDXHgBXAQAgAAkJ5xDXHgBXAQAAAA==.Tayoma:BAAALgAECgEJAwAAAA==.Tazara:BAAALgAECgUJBwAAAA==.',
Te='Tealth:BAAALgAECgYJBgAAAA==.Ted:BAABLgAECn8kAAIDAAgJghZkJQC+AQADAAgJghZkJQC+AQAAAA==.Tehgermza:BAAALgAECgcJBwAAAA==.Tehgrimza:BAABLgAECn8vAAMfAAkJ/hv2AAC2AQAfAAkJ/hv2AAC2AQAiAAEJrxCDdAAwAAAAAA==.Teias:BAAALgAECggJCgABLgAFFAUJFQAWAEUaAA==.Teka:BAAALgADCgMJAwAAAA==.Temu:BAAALgAECgYJCAABLgAFFAQJDQAfAFcXAA==.Tet:BAACLgAFFH8HAAIPAAMJAQ8rRACjAAAPAAMJAQ8rRACjAAAuAAQKfxkAAg8ACAkyH6QQAMwCAA8ACAkyH6QQAMwCAAAA.Tevia:BAABLgAECn8tAAINAAkJ4xicDQAOAgANAAkJ4xicDQAOAgAAAA==.',
Th='Thalip:BAAALgAECgQJBwAAAA==.Thekingheals:BAAALgAECgUJCAAAAA==.Thokmay:BAABLgAECn8pAAIpAAkJZxFFIACrAQApAAkJZxFFIACrAQAAAA==.Thorel:BAAALgAECgQJBwAAAA==.Thornar:BAAALgAECgUJBQAAAA==.Thunden:BAAALgAFFAEJAQAAAA==.Thyeth:BAAALgADCgEJAQAAAA==.',
Ti='Tiandrinna:BAABLgAECn8qAAIOAAkJKxxXAgA+AgAOAAkJKxxXAgA+AgAAAA==.Tightywhitey:BAAALgAECggJDwAAAA==.Timkaoss:BAABLgAECn8dAAMPAAYJtBe2VgA2AQAPAAYJtBe2VgA2AQALAAMJNQfwfQBLAAAAAA==.Timmyjudge:BAAALgAECgYJCAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAABLgAECn8tAAIMAAgJqQY3KADyAAAMAAgJqQY3KADyAAAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgkJFgAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgQJCAABLgAECgkJLQACALMiAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgAECgUJEAAAAA==.Trixterwolf:BAAALgAECgEJAQAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAACLgAFFH8NAAIGAAMJehFefwDYAAAGAAMJehFefwDYAAAuAAQKfy0AAgYACQlcGRg8ACoCAAYACQlcGRg8ACoCAAAA.',
Ty='Tygrassar:BAAALgAECgIJAgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8wAAIWAAkJVh3nCADaAgAWAAkJVh3nCADaAgAAAA==.',
['Tä']='Täd:BAABLgAECn8XAAIfAAYJ/RHeiQAmAQAfAAYJ/RHeiQAmAQAAAA==.',
Un='Unholycreep:BAAALgAFFAEJAgABLgAFFAQJCQAMAGwcAA==.',
Va='Vaelenka:BAAALgADCgMJAwAAAA==.Vaelune:BAAALgAECgYJBgAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAABLgAECn8jAAMIAAgJ9QvAEwBAAQAIAAgJXAvAEwBAAQAZAAYJPAkg0ADoAAAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAACLgAFFH8GAAIJAAMJlQ8odADLAAAJAAMJlQ8odADLAAAuAAQKfyIAAgkACAlXHs48ABECAAkACAlXHs48ABECAAAA.Valicous:BAAALgAECgUJDgAAAA==.Valyerian:BAABLgAECn8uAAIUAAgJ5hsOFgCcAgAUAAgJ5hsOFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgkJHgAHAGMiAA==.Vandevoker:BAAALgAECgQJCAABLgAECgkJHgAHAGMiAA==.Vanserra:BAAALgADCgcJEAAAAA==.Varregory:BAAALgADCgUJBAAAAA==.Vaxas:BAABLgAECn8jAAIJAAgJ1h/KMgA1AgAJAAgJ1h/KMgA1AgAAAA==.Vaxasus:BAAALgAECgEJAQAAAA==.Vaylorian:BAABLgAECn8VAAIgAAYJFyACEwDDAQAgAAYJFyACEwDDAQAAAA==.Vaült:BAABLgAECn85AAMhAAkJ8hiHDwCgAgAhAAkJ8hiHDwCgAgAJAAMJPwYbEgFzAAAAAA==.',
Ve='Velystana:BAAALgADCgIJAgAAAA==.Verianna:BAABLgAECn83AAQHAAkJmiVLAQBRAwAHAAkJFSVLAQBRAwAZAAgJZyERMAA/AgAIAAUJlhqRDwB9AQAAAA==.Vexmorphis:BAAALgAECgMJBAABLgAECgkJHgAJAJwSAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgAECgQJBAAAAA==.',
Vr='Vraknaar:BAAALgAECgMJAwAAAA==.',
Vt='Vtown:BAAALgAECgMJBgAAAA==.',
Wa='Wadumu:BAABLgAECn8xAAMPAAgJXAwOaQAYAQAPAAYJVg4OaQAYAQAgAAgJlwskLwDwAAAAAA==.Wagwanmist:BAABLgAECn8tAAIRAAgJtBmgHQAsAgARAAgJtBmgHQAsAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warrdaddy:BAAALgAECgIJAwAAAA==.Warvegas:BAAALgAECgUJDAAAAA==.Warwulf:BAAALgAECgQJBAABLgAECggJJQAUADwcAA==.Water:BAAALgADCgEJAQAAAA==.',
Wi='Willowy:BAABLgAECn9CAAIGAAkJvyMXCwAgAwAGAAkJvyMXCwAgAwAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8cAAQCAAUJ4hNCeAD1AAACAAUJ4hNCeAD1AAADAAQJ6wjhfQB3AAAjAAEJngq8PwAxAAAAAA==.',
Xa='Xaerius:BAABLgAECn9HAAMUAAkJEBqfEgBeAgAUAAkJEBqfEgBeAgANAAEJ6wUlhgAjAAAAAA==.Xalatath:BAAALgAECgYJBwAAAA==.Xan:BAABLgAECn8gAAIGAAkJyRfOUQDnAQAGAAkJyRfOUQDnAQAAAA==.Xann:BAAALgAECgIJAgAAAA==.Xannen:BAAALgADCgkJCQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAABLgAECn8YAAMGAAgJ4yBnIwCPAgAGAAgJ6h9nIwCPAgAoAAIJyCAeDAC9AAAAAA==.Xashadin:BAAALgAECgcJBwAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIGAAcJJiNIPQCCAgAGAAcJJiNIPQCCAgAAAA==.',
Xo='Xog:BAAALgAECgIJAgAAAA==.',
Ya='Yarman:BAABLgAECn8tAAIBAAgJcRY7HgC0AQABAAgJcRY7HgC0AQAAAA==.',
Ye='Yeaforpie:BAABLgAECn8sAAMnAAkJMBR5AABgAQAfAAgJ8Q/BXACIAQAnAAkJEBR5AABgAQAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAABLgAECn8YAAIhAAgJ7BQJLACxAQAhAAgJ7BQJLACxAQAAAA==.',
Yo='Yoshial:BAABLgAECn8gAAIGAAYJLwim2ADlAAAGAAYJLwim2ADlAAAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAABLgAECn8+AAMXAAkJQxtYDQB+AgAXAAkJQxtYDQB+AgAYAAYJPA0HQgACAQAAAA==.',
Ze='Zealins:BAAALgAECgQJBAAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zerastar:BAAALgAECgQJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQABLgAFFAUJFAAJAOskAA==.Zirou:BAAALgAFFAIJAwABLgAFFAMJCAAeACMhAA==.Ziv:BAACLgAFFH8VAAIPAAUJ4xlDGACdAQAPAAUJ4xlDGACdAQAuAAQKfzYAAg8ACQkqINEIACsDAA8ACQkqINEIACsDAAEuAAUUAwkIAB4AIyEA.Ziyn:BAACLgAFFH8IAAIeAAMJIyG8FwAUAQAeAAMJIyG8FwAUAQAuAAQKfxgAAx4ACQk+HmkHAKgCAB4ACQk+HmkHAKgCAAoABgmuGnJ9AEQBAAAA.',
Zo='Zoda:BAAALgAECgIJAwAAAA==.',
Zx='Zxno:BAAALgAECgEJAQAAAA==.Zxolgarai:BAAALgAECgEJAQAAAA==.',
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
