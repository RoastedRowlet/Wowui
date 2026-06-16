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

local lookup = {'Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Mage-Fire','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Warrior-Arms','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Unholy','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Warlock-Demonology','Druid-Guardian','Paladin-Holy','Warlock-Destruction','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Evoker-Preservation','Warlock-Affliction','Mage-Arcane','Monk-Windwalker',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aarztok:BAAALgAECgUJBQABLgAFFAcJFgABAOwZAA==.',
Ac='Achepir:BAAALgADCgIJAgAAAA==.Achiella:BAAALgAECgEJAQAAAA==.',
Ad='Advisor:BAACLgAFFH8KAAICAAQJkRBWPgDkAAACAAQJkRBWPgDkAAAuAAQKfzQAAwIACQmcJG0JAOECAAIACQmcJG0JAOECAAMAAQl5F3WWAEQAAAAA.',
Ae='Aería:BAAALgAECgYJDwAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgAECgEJAQAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgADCgcJBwAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aldoraine:BAAALgAECgEJAgABLgAECgEJAgAEAAAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Altrix:BAAALgAECgQJBAABLgAFFAIJBAAEAAAAAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgADCgcJEAAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgAECgQJCAAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Andolas:BAAALgADCgYJCQAAAA==.Angelicuss:BAAALgAECgUJBgABLgAECgkJQQAFAL8jAA==.Annya:BAAALgAECgcJBwAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aparajita:BAAALgAECgEJAwABLgABCgMJAwAEAAAAAA==.Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCwAAAA==.Aristoleh:BAAALgAECgEJAQABLgAFFAcJEwADANgOAA==.Arkahera:BAAALgAECgQJBQABLgAFFAcJFgABAOwZAA==.Arolder:BAABLgAECn8mAAMGAAkJqyFQBgC7AgAGAAkJdSFQBgC7AgAHAAcJZB3dAwA6AgAAAA==.Arredin:BAAALgADCgYJBgAAAA==.Arturium:BAAALgADCgYJCwAAAA==.',
As='Astayuno:BAAALgAECgQJBAAAAA==.',
At='Atabey:BAABLgAECn87AAIIAAkJICKfEADfAgAIAAkJICKfEADfAgABLgABCgMJAwAEAAAAAA==.Atimusk:BAAALgADCggJDwABLgAECgYJCgAEAAAAAA==.Atoadaso:BAAALgAECggJDAAAAA==.Attretes:BAAALgADCgcJDwAAAA==.',
Az='Azazél:BAAALgAECgEJAQABLgAFFAQJCQAFACYKAA==.Azcowboy:BAAALgAECgUJEAAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgAECgYJCAAAAA==.',
Ba='Badco:BAAALgAECgQJBAAAAA==.Balacheck:BAABLgAECn8eAAIJAAgJUAVqiQAnAQAJAAgJUAVqiQAnAQAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgADCgQJCgAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAABLgAECn8rAAIKAAkJbxw7DACQAgAKAAkJbxw7DACQAgAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgYJFAAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAAFAKAcAA==.',
Bi='Bigbadwoof:BAAALgADCgYJIQAAAA==.Bighog:BAACLgAFFH8UAAILAAQJGyHrDABVAQALAAQJGyHrDABVAQAuAAQKfxYAAgsABwloJkkHAI4CAAsABwloJkkHAI4CAAAA.Bipbipbup:BAAALgAECgEJAQAAAA==.',
Bj='Björn:BAAALgADCgcJBwAAAA==.',
Bl='Blaazzin:BAAALgADCgcJHgAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Blinck:BAAALgAECgUJBQAAAA==.Blinkz:BAAALgAECgUJBQAAAA==.Bloomzy:BAACLgAFFH8HAAIFAAMJFiEzbAASAQAFAAMJFiEzbAASAQAuAAQKfy4AAwUACQluGpI0AEQCAAUACQluGpI0AEQCAAwAAgl6G1oKAJ8AAAAA.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAAALgAFFAIJBAAAAA==.Boombástic:BAABLgAECn8oAAMKAAkJaQ8YLAByAQAKAAgJMhAYLAByAQANAAIJ0A9hpABmAAAAAA==.Boomco:BAABLgAECn8cAAIJAAgJOBHlUQCpAQAJAAgJOBHlUQCpAQAAAA==.Bootes:BAAALgAECgMJAwAAAA==.Bors:BAAALgADCgUJEAAAAA==.Boulderholdr:BAAALgAECgUJDwAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Bravillius:BAAALgADCgkJDQAAAA==.Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAAALgAECgcJEwAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAIOAAkJyRmeCgAkAgAOAAkJyRmeCgAkAgAAAA==.Bryda:BAAALgAECgQJCgAAAA==.',
Bu='Bubblez:BAAALgAECgUJBQAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAABLgAECn8UAAIBAAUJeg7eTwC/AAABAAUJeg7eTwC/AAAAAA==.',
Ca='Cajbo:BAABLgAECn86AAIPAAkJ9R/UAQDaAgAPAAkJ9R/UAQDaAgAAAA==.Calyssa:BAABLgAECn8eAAIIAAgJ6w7fiQBaAQAIAAgJ6w7fiQBaAQAAAA==.Candyflöss:BAACLgAFFH8JAAILAAQJbBxpEgANAQALAAQJbBxpEgANAQAuAAQKfyAAAwsABgkuJH0OAP8BAAsABgkuJH0OAP8BABAAAQkLEHR2ADAAAAAA.Capmkrunch:BAAALgAECgEJAgABLgAECggJDAAEAAAAAA==.Caraling:BAAALgADCgYJBwAAAA==.Caralynn:BAAALgAECgUJDQAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAACLgAFFH8HAAIRAAQJJhSgLQD3AAARAAQJJhSgLQD3AAAuAAQKf0QAAhEACQkbIbQFAEoDABEACQkbIbQFAEoDAAAA.Castisteus:BAAALgAECgYJCAAAAA==.Cathelina:BAAALgADCggJFQAAAA==.Cathom:BAAALgAECgUJCgAAAA==.',
Ch='Charcasm:BAAALgAECgYJCAAAAA==.Charizaard:BAAALgAECgYJCQAAAA==.Charizaardx:BAACLgAFFH8PAAMSAAYJwgiNBwDFAAATAAUJqwPvMwDxAAASAAQJrAyNBwDFAAAuAAQKf0YAAxIACQncGR8EADcCABIACQn1GB8EADcCABMACAnRFPYlAI0BAAAA.Chevytron:BAAALgAECgYJEwAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8bAAMUAAcJSxBtXADfAAAUAAYJYQ9tXADfAAALAAMJzgz9RQBWAAAAAA==.Clives:BAAALgAECgEJAQAAAA==.Clmx:BAAALgADCgIJAgAAAA==.Clément:BAAALgADCgUJBgAAAA==.',
Co='Coffeebeans:BAABLgAECn8iAAMNAAgJExbjPgCnAQANAAcJfxTjPgCnAQAKAAgJwAu7NQA8AQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowdeath:BAAALgADCgEJAQAAAA==.Cowkiller:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgYJDgAAAA==.Creslan:BAAALgAECgYJBgABLgAECgkJTwAVACsfAA==.Crimsonthot:BAAALgAECggJCwAAAA==.Crogan:BAABLgAECn8UAAQWAAkJzAgyNQApAQAWAAgJJwkyNQApAQAXAAUJJAixWgCnAAAYAAEJ+gVAWgAuAAAAAA==.Crysiscane:BAAALgADCgYJBQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQABLgAECggJDAAEAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgAECgYJBwAAAA==.Dagul:BAAALgAECgcJCwAAAA==.Dalna:BAABLgAECn83AAIRAAkJQxhTEgCGAgARAAkJQxhTEgCGAgAAAA==.Danilex:BAABLgAECn8cAAIFAAgJCx9pSABeAgAFAAgJCx9pSABeAgABLgAFFAgJMwAYAMEbAA==.Danksoul:BAAALgAECgkJAQABLgAFFAIJAgAEAAAAAA==.Darat:BAAALgADCgEJAQAAAA==.Darcorin:BAABLgAECn8fAAIZAAgJIBYobgCGAQAZAAgJIBYobgCGAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAABLgAECn8ZAAIJAAcJMQfckgAVAQAJAAcJMQfckgAVAQAAAA==.Darksaber:BAABLgAECn8UAAIKAAUJlQvmWACqAAAKAAUJlQvmWACqAAAAAA==.Dasthodan:BAAALgAECgQJBwAAAA==.Dayne:BAAALgAECgcJDQAAAA==.',
Dc='Dctrpepper:BAAALgAECgIJAgAAAA==.',
De='Deathcore:BAAALgADCgkJEwAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathtardza:BAAALgAECgQJBAAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8xAAQKAAkJJQSIRAD2AAAKAAkJJQSIRAD2AAANAAkJHAb/awDuAAAaAAIJhQCIOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Delvisprezly:BAAALgAECggJDAAAAA==.Demonica:BAABLgAECn8pAAQbAAkJ+wgPEgApAQAbAAkJ4wcPEgApAQAcAAUJ4gYqRADmAAAdAAIJwwyA7QBdAAAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Demonspecial:BAAALgAECgkJBwAAAA==.Denastus:BAAALgAECgUJBQAAAA==.Dethknyght:BAAALgAECgkJCgABLgAFFAcJFgABAOwZAA==.Detoxin:BAAALgAECgIJAgAAAA==.Devick:BAAALgAECgEJAQAAAA==.',
Di='Dinta:BAABLgAECn9QAAIIAAkJ4xuiGwCcAgAIAAkJ4xuiGwCcAgAAAA==.Dionysys:BAAALgAECgEJAgABLgABCgMJAwAEAAAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAABLgAECn8cAAIJAAgJ0BrlKwApAgAJAAgJ0BrlKwApAgAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgAECgMJAwAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8fAAIBAAkJLhW1FgDyAQABAAkJLhW1FgDyAQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8sAAIeAAkJTg2JGQDTAQAeAAkJTg2JGQDTAQAAAA==.Dummblond:BAACLgAFFH8QAAMNAAQJfAerOwC7AAANAAQJfAerOwC7AAAKAAIJMwU7QwBiAAAuAAQKfx4AAw0ACAlrEec6AKYBAA0ACAlrEec6AKYBAAoABwkxCGxZAL4AAAAA.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAABLgAECn8XAAIfAAcJKB2EUQCmAQAfAAcJKB2EUQCmAQAAAA==.',
Dy='Dyonesa:BAAALgAECgUJBQAAAA==.Dysfunction:BAABLgAECn8UAAIgAAgJwRGyHQBaAQAgAAgJwRGyHQBaAQAAAA==.',
Ea='Earthshield:BAAALgAECgYJDQABLgAECgkJPwAhADckAA==.',
Eg='Ego:BAABLgAECn8iAAIhAAkJPyKsBQAzAwAhAAkJPyKsBQAzAwAAAA==.',
El='Elipto:BAAALgAECgYJBgAAAA==.Ellaana:BAAALgAECgUJEAAAAA==.Elotarra:BAAALgAECgEJAQAAAA==.Elowentinsel:BAAALgAECgEJAQAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgAECgMJAwAAAA==.',
En='Enduran:BAAALgAECgYJDQAAAA==.',
Er='Erasi:BAABLgAECn8zAAMXAAkJVAquKwB1AQAXAAkJVAquKwB1AQAWAAUJzwLyXABhAAAAAA==.',
Es='Es:BAABLgAECn8UAAIZAAcJ8wTGpgA0AQAZAAcJ8wTGpgA0AQAAAA==.Escanorlion:BAAALgADCgcJBwAAAA==.Esileda:BAAALgAECgQJBAAAAA==.Esttsumi:BAAALgAECgkJDwAAAA==.',
Eu='Euphia:BAAALgAECgUJDAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8pAAIJAAkJqhBuOQDJAQAJAAkJqhBuOQDJAQAAAA==.Exodiá:BAAALgAECgUJBQAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8uAAIIAAkJVB2zIACCAgAIAAkJVB2zIACCAgAAAA==.Faethe:BAAALgAECgEJAgABLgAECgkJQQAFAL8jAA==.Faithfulpain:BAAALgADCgYJBgAAAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farmerpolly:BAAALgADCgYJCQAAAA==.Farwolf:BAABLgAECn8oAAIJAAgJWArVcwBTAQAJAAgJWArVcwBTAQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECggJBwABLgAFFAIJAwAEAAAAAA==.Fee:BAACLgAFFH8bAAIIAAUJoyWrFQCxAQAIAAUJoyWrFQCxAQAuAAQKfzwAAggACQmSJPEHACoDAAgACQmSJPEHACoDAAAA.Fellyn:BAAALgAECgQJBAAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgAECgMJAwAAAA==.Festerr:BAAALgADCgQJAQAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.Fishstick:BAAALgAECgkJDQAAAA==.',
Fl='Flameheart:BAABLgAECn8cAAMiAAgJqQoXEwAWAQAiAAgJqQoXEwAWAQAfAAEJAAIJZAEPAAAAAA==.Fleathulhu:BAACLgAFFH8MAAIWAAMJahHEIQCmAAAWAAMJahHEIQCmAAAuAAQKfzQAAhYACQn0HTQHAPoCABYACQn0HTQHAPoCAAAA.Flungpu:BAAALgADCgkJFwABLgAECgkJMwAJAJwRAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAABLgAECn8kAAMfAAgJkg/rXwCAAQAfAAgJkg/rXwCAAQAiAAEJvRIOPQA0AAAAAA==.Foxieshoxie:BAAALgAECgEJAwAAAA==.Foxylocksy:BAAALgADCgkJCgAAAA==.',
Fr='Frontierland:BAAALgADCgcJDQAAAA==.Frostdoom:BAAALgADCgYJCAAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgADCggJCAAAAA==.',
Fu='Furgy:BAAALgAECgEJAQAAAA==.Furrfoxsake:BAAALgAECgQJBwABLgAECggJDwAEAAAAAA==.Fuzball:BAAALgADCgEJAQAAAA==.Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Galfure:BAAALgADCgYJBgAAAA==.Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAEAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn83AAIPAAkJhRZSBgACAgAPAAkJhRZSBgACAgAAAA==.',
Ge='Genovefa:BAAALgAECgIJAgAAAA==.',
Gh='Ghoulmaxing:BAAALgAFFAIJAwAAAA==.Ghøulish:BAAALgAECgUJBwABLgAECggJMQANAFwMAA==.',
Gi='Gimper:BAAALgADCgcJFwAAAA==.',
Gl='Glaistia:BAAALgADCgIJAgAAAA==.Glen:BAAALgAECgUJEAAAAA==.Glowstik:BAAALgAECgQJBAAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.Gormlaîth:BAAALgAECgQJBwABLgAECgYJCgAEAAAAAA==.',
Gr='Grabmymelonz:BAAALgAECgUJBQAAAA==.Graeman:BAAALgADCgMJAwAAAA==.Grandpaslay:BAAALgAECgQJCQAAAA==.Greatpàw:BAAALgAECgEJAQAAAA==.Grisly:BAAALgADCgUJBQAAAA==.',
Gu='Gurrney:BAAALgADCgYJBgAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgAECgYJEQAAAA==.Habbypallie:BAAALgADCgYJFAAAAA==.Haimanist:BAABLgAECn8ZAAIOAAgJliAlAwDwAgAOAAgJliAlAwDwAgABLgAFFAcJFgABAOwZAA==.Halixan:BAABLgAECn8gAAIjAAkJWyPeAgDjAgAjAAkJWyPeAgDjAgAAAA==.Handlebardoc:BAACLgAFFH8OAAIZAAQJnxjkYgAuAQAZAAQJnxjkYgAuAQAuAAQKf0AAAhkACQleIiASANsCABkACQleIiASANsCAAAA.Harmoni:BAAALgAECgIJAgABLgAECgkJQQAFAL8jAA==.Hatorade:BAAALgAECgUJBQAAAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgAECgkJBQAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgkJEQAAAA==.',
Ho='Holyname:BAAALgAECgQJAwAAAA==.Holysim:BAAALgAECgEJAQAAAA==.',
Hu='Hunteð:BAAALgAECgEJAgAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgAECgIJAgAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8yAAMiAAkJHwyrFQD3AAAfAAkJ0AjXbwBaAQAiAAYJGw6rFQD3AAAAAA==.',
Ir='Ireus:BAAALgAECgIJAgAAAA==.Ironfizt:BAAALgAECggJDwABLgAECggJJQAkAOMZAA==.',
Is='Islet:BAAALgADCgMJAwAAAA==.Istia:BAAALgADCgUJBQAAAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.',
Iu='Iudex:BAAALgAECggJDwAAAA==.Iutu:BAAALgAECgQJBAAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAABLgAECn8/AAMhAAkJNyRFAgBYAwAhAAkJNyRFAgBYAwAIAAgJRQ/0ggBmAQAAAA==.Jarvy:BAAALgAECggJCAAAAA==.',
Je='Jedavon:BAAALgAECgEJAQAAAA==.Jenhadin:BAAALgAECgUJBQAAAA==.Jerreden:BAAALgADCgYJBgAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.Jestic:BAABLgAECn8aAAIkAAkJ7A4VFwDfAQAkAAkJ7A4VFwDfAQAAAA==.',
Ji='Jiangshi:BAAALgAECgYJCgAAAA==.Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ju='Justpwnedu:BAAALgAECgkJCgAAAA==.',
Ka='Kaazel:BAABLgAECn8zAAIJAAkJnBEGNwD9AQAJAAkJnBEGNwD9AQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgYJEgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgAECggJDQAAAA==.Kamsham:BAAALgAECgEJAQABLgAECgkJHAABAEwSAA==.Kandiquake:BAAALgAECgIJAgAAAA==.Karea:BAAALgAECgcJDgAAAA==.Karite:BAABLgAECn80AAIlAAkJ/iJ5AQDhAgAlAAkJ/iJ5AQDhAgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAIRAAgJRxkeHgAiAgARAAgJRxkeHgAiAgAAAA==.Karveila:BAAALgAECgQJBAAAAA==.Katyla:BAAALgADCgQJBAABLgAECgkJMwAJAOoMAA==.Kazar:BAAALgADCgcJDwAAAA==.Kazenoth:BAABLgAECn8rAAMTAAkJxxpGFwAcAgATAAkJxxpGFwAcAgAmAAEJbxGvOwAyAAAAAA==.',
Ke='Kellement:BAAALgAECgUJBQAAAA==.Ken:BAABLgAECn8YAAIKAAgJVBZ7HADhAQAKAAgJVBZ7HADhAQABLgAECgkJRAAfAHEaAA==.Kennychaoss:BAABLgAECn8sAAMCAAkJ7xxGDQDqAgACAAkJ7xxGDQDqAgADAAcJZw2zRgAVAQAAAA==.',
Kh='Khrisbkreme:BAAALgAECgEJAQABLgAECggJDAAEAAAAAA==.',
Ki='Kille:BAABLgAECn8dAAIJAAgJbhYTOwDvAQAJAAgJbhYTOwDvAQAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Kobeqt:BAAALgAECgEJAQAAAA==.Koland:BAAALgADCgkJDwAAAA==.Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn81AAIKAAkJ4w0uJgCYAQAKAAkJ4w0uJgCYAQAAAA==.Kostazu:BAABLgAECn9VAAIDAAkJuhICIgDRAQADAAkJuhICIgDRAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAFFAUJGwAIAKMlAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAFFAMJDAAWAGoRAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAgABLgAECgMJBgAEAAAAAA==.',
La='Laity:BAABLgAECn9OAAIIAAkJEyFMCgATAwAIAAkJEyFMCgATAwAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Laraithe:BAAALgADCgEJAQAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgAECgEJAQAAAA==.Lazraar:BAAALgAECgEJAQAAAA==.Lazylaz:BAABLgAECn8vAAIaAAkJNyQwAgAKAwAaAAkJNyQwAgAKAwABLgAFFAgJIgAZAAEeAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAABLgAECn8zAAIjAAgJRCLYAwC7AgAjAAgJRCLYAwC7AgAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJCQAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAABLgAECn8pAAMcAAgJ6BUoIgBhAQAcAAYJUxgoIgBhAQAdAAgJlwyVagBLAQAAAA==.Lifebloom:BAAALgAECgIJAgABLgAECgkJPwAhADckAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAFFAMJCAAeACMhAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8zAAIJAAkJ6gzpUgCmAQAJAAkJ6gzpUgCmAQAAAA==.Livedcargox:BAAALgAECgYJBgAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Loqir:BAAALgAFFAIJAwABLgAFFAcJHAATAE8aAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgAECgEJAQAAAA==.',
Ly='Lycanbyte:BAAALgAECgYJEQAAAA==.Lylith:BAABLgAECn82AAMcAAkJLBfrEQAJAgAcAAkJLBfrEQAJAgAdAAQJawXi6QBiAAAAAA==.Lyphiandraa:BAAALgAECgEJAQAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJBgAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Maddicollins:BAAALgAECgYJDAABLgAFFAIJBwAIANcbAA==.Magdalena:BAABLgAECn84AAIJAAkJjg6NRgDJAQAJAAkJjg6NRgDJAQAAAA==.Magehawk:BAAALgAECgUJBQAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magmaface:BAAALgAECgYJBwAAAA==.Magnólia:BAABLgAECn8tAAICAAkJsyKjCAAkAwACAAkJsyKjCAAkAwAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Maithre:BAAALgAECgIJAwAAAA==.Makima:BAAALgADCgcJCQABLgAFFAQJCQAfABAXAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Maribelle:BAAALgAECggJDAABLgAECgkJQQAFAL8jAA==.Marrent:BAAALgADCgcJGQAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJDAAAAA==.Mazeltov:BAABLgAECn8WAAILAAgJPRrNDgAcAgALAAgJPRrNDgAcAgAAAA==.',
Me='Melomel:BAABLgAECn8lAAIjAAgJ7hFIEQCaAQAjAAgJ7hFIEQCaAQAAAA==.Melonsquezer:BAABLgAECn83AAMOAAkJsh65BQCPAgAOAAkJsh65BQCPAgAIAAEJ2RNhjwEwAAAAAA==.Menmei:BAABLgAECn8qAAIJAAgJlBNZQwDTAQAJAAgJlBNZQwDTAQAAAA==.Mexicanrage:BAAALgADCgQJBAAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgAECgUJEAAAAA==.Minien:BAABLgAECn8zAAMjAAkJcRxWCwD8AQAjAAgJ+RtWCwD8AQADAAgJeRhKIwDIAQAAAA==.Minko:BAABLgAECn8rAAIJAAkJIhtCHwBnAgAJAAkJIhtCHwBnAgAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAFFAQJCQAFACYKAA==.',
Mo='Modelo:BAAALgAFFAEJAQAAAA==.Molulu:BAAALgADCgcJCwABLgAECgYJGgAFANMHAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn9PAAIVAAkJKx+UAgDBAgAVAAkJKx+UAgDBAgAAAA==.Morillic:BAABLgAECn8YAAQnAAcJqxgvCwCmAQAnAAcJqxgvCwCmAQAiAAMJrA0MSACWAAAfAAIJMxSCCgFIAAABLgAECggJGgAXABgWAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgAECgEJAQAAAA==.',
Ms='Mstrcrowly:BAABLgAECn8qAAMfAAgJZyCRFwCVAgAfAAgJZyCRFwCVAgAnAAIJvhy3OABAAAAAAA==.',
Mu='Mustachjones:BAABLgAECn81AAIfAAkJERzEHwBkAgAfAAkJERzEHwBkAgAAAA==.',
My='Myros:BAABLgAECn86AAMFAAkJfBbAQgARAgAFAAkJfBbAQgARAgAMAAEJ8gX5FAApAAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgAECgcJDAAAAA==.Narestor:BAABLgAECn8YAAIUAAgJHRPBMQDlAQAUAAgJHRPBMQDlAQABLgAFFAUJEwATALoMAA==.Nasril:BAAALgAECggJEgAAAA==.Nazervis:BAAALgAECgUJBQABLgAFFAgJIgAZAAEeAA==.Nazurend:BAABLgAECn8pAAMFAAkJJRQ3RQAJAgAFAAkJJRQ3RQAJAgAMAAEJ9QVqFQAmAAAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAFFAEJAgAAAA==.Nemesîs:BAAALgADCgkJGwAAAA==.Nero:BAABLgAECn8nAAIcAAkJTyEjCACpAgAcAAkJTyEjCACpAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMfAAgJNAUjfQBhAQAfAAgJNAUjfQBhAQAiAAIJywFjZgBDAAAAAA==.Nimuerose:BAAALgADCgMJAwAAAA==.',
No='Nortree:BAABLgAECn8nAAINAAgJlhHBOgCnAQANAAgJlhHBOgCnAQAAAA==.Nost:BAABLgAECn8sAAIIAAgJDhyBPwAGAgAIAAgJDhyBPwAGAgAAAA==.Notalock:BAAALgADCgIJAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.Novena:BAAALgAECgQJBAABLgAECgkJLQACALMiAA==.',
Nu='Nulwyrm:BAABLgAECn8rAAMTAAkJQBs7EABkAgATAAkJQBs7EABkAgASAAEJohjJIABKAAAAAA==.Numira:BAAALgADCgMJAwAAAA==.',
Ny='Nymue:BAAALgAECgMJAwAAAA==.Nyyrivik:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8tAAICAAgJRR8kGACFAgACAAgJRR8kGACFAgAAAA==.',
Oh='Ohitsadragon:BAACLgAFFH8FAAISAAIJrwoGCgCCAAASAAIJrwoGCgCCAAAuAAQKfyAAAhIACAkMFQIIALEBABIACAkMFQIIALEBAAAA.',
On='Ono:BAAALgAECgEJAQAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAEAAAAAA==.Oreoscruunit:BAAALgAECgEJAgABLgAECggJDAAEAAAAAA==.',
Ow='Owl:BAABLgAECn8fAAInAAkJAwxUDQBgAQAnAAkJAwxUDQBgAQAAAA==.Owlcatraz:BAACLgAFFH8OAAINAAUJgwe/LQD2AAANAAUJgwe/LQD2AAAuAAQKfxUAAwoACAlXGq4ZAPsBAAoACAlXGq4ZAPsBAA0ABQknC6t2AM8AAAAA.',
Pa='Paendrag:BAAALgAECgUJBQAAAA==.Paladinna:BAAALgADCgMJAwAAAA==.Panadarama:BAACLgAFFH8WAAIBAAcJ7BmJCQDsAQABAAcJ7BmJCQDsAQAuAAQKfygAAgEACAkWJWgEAEUDAAEACAkWJWgEAEUDAAAA.Pandmei:BAAALgADCgkJCQAAAA==.Panteragon:BAABLgAECn8oAAIeAAgJFwhSJwBkAQAeAAgJFwhSJwBkAQAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAABLgAECn8iAAIJAAgJwQm6bABjAQAJAAgJwQm6bABjAQAAAA==.',
Pe='Peachyboy:BAAALgADCgMJAwAAAA==.Periwinkle:BAABLgAECn8eAAIWAAgJZg8sKACAAQAWAAgJZg8sKACAAQAAAA==.Persaud:BAACLgAFFH8TAAMnAAUJrRkSCAD0AAAfAAUJLxcZSQAwAQAnAAMJwRUSCAD0AAAuAAQKfxwAAyIACQkkGtsPANEBACIABwmeEtsPANEBAB8ABQn0HvRQAKgBAAAA.',
Ph='Phidra:BAABLgAECn9FAAMCAAkJIw/7OgC+AQACAAkJIw/7OgC+AQADAAQJTga/agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgAECgYJGgAFANMHAA==.Phranky:BAAALgAECgEJBAABLgAECggJDAAEAAAAAA==.Phytos:BAAALgAECgEJAQAAAA==.',
Pi='Pixiebrew:BAAALgAECgUJDgAAAA==.Pizzagirl:BAAALgAECgYJBgAAAA==.',
Pl='Plutrax:BAAALgAECgYJDwAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.',
Pr='Predatorc:BAABLgAECn8dAAIJAAkJaArHTgB9AQAJAAkJaArHTgB9AQAAAA==.Prepotêntê:BAAALgAECgYJCgAAAA==.Primevil:BAAALgAECgcJEwAAAA==.Primevl:BAAALgAECggJDwAAAA==.Primévil:BAABLgAECn80AAIdAAkJ4AwOWAB7AQAdAAkJ4AwOWAB7AQAAAA==.',
Pu='Puma:BAAALgAECgYJEwAAAA==.',
Py='Pyrissa:BAAALgADCgEJAQAAAA==.',
['Pí']='Píp:BAAALgADCggJDQAAAA==.',
Qu='Quarz:BAAALgAECgMJBAAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.Quoternion:BAAALgAECgEJAQAAAA==.',
Ra='Raden:BAAALgADCgQJBQAAAA==.Raediant:BAAALgAECgUJBwABLgAECgkJHwABAC4VAA==.Raelek:BAAALgAECgQJBAAAAA==.Ragethecage:BAAALgADCgMJAwAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Ragsonfire:BAAALgADCgIJAgAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8lAAMUAAgJPBwjHQAEAgAUAAgJPBwjHQAEAgALAAcJrRRHHgA+AQAAAA==.Raquel:BAABLgAECn8jAAICAAkJJQtvRwBkAQACAAkJJQtvRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAAALgAECggJDwAAAA==.',
Re='Rede:BAAALgAECgIJAwAAAA==.Reeyou:BAAALgAECggJDAABLgAECgkJRAAfAHEaAA==.Reign:BAACLgAFFH8JAAIFAAQJJgp4aAAbAQAFAAQJJgp4aAAbAQAuAAQKf0gAAgUACQngGe0jAIsCAAUACQngGe0jAIsCAAAA.Reilu:BAAALgADCgIJAgAAAA==.Relieff:BAAALgAECgYJEwAAAA==.Relmin:BAAALgAECgEJAQAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.Revival:BAAALgAECgYJBwABLgAECgkJPwAhADckAA==.',
Ri='Rio:BAABLgAECn9DAAIcAAkJSh8XBgDWAgAcAAkJSh8XBgDWAgAAAA==.Ris:BAABLgAECn84AAIFAAkJtB9QGADFAgAFAAkJtB9QGADFAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgAECgMJAwAAAA==.Rockyrogue:BAABLgAECn8ZAAIkAAgJ5ATuMgAKAQAkAAgJ5ATuMgAKAQAAAA==.Roknathar:BAABLgAECn8xAAMVAAkJyCXBAgC4AgAVAAgJwSXBAgC4AgAJAAMJ4R7olgANAQAAAA==.Rolldemort:BAAALgAECgIJAwAAAA==.Ronburrgandy:BAAALgAECgEJAQAAAA==.Ronilf:BAABLgAECn8lAAIkAAgJ4xlVFwDdAQAkAAgJ4xlVFwDdAQAAAA==.Rono:BAAALgADCggJEwAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8oAAMXAAkJURwpFAAtAgAXAAkJURwpFAAtAgAWAAIJyhN8iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgAECgcJCAAAAA==.Rukaza:BAAALgAECgEJAQABLgAFFAUJDwAdAJ0cAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Sabrilla:BAAALgAECgQJAwAAAA==.Saerenity:BAAALgAECgMJAwAAAA==.Sahala:BAAALgADCgEJAQAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgAECgEJAQAAAA==.Sana:BAACLgAFFH8JAAMDAAQJyxaTHAAwAQADAAQJyxaTHAAwAQACAAIJpQJjcQBVAAAuAAQKfzAAAwMACQnYIG4IANQCAAMACQnYIG4IANQCAAIAAQlSDyrWAC4AAAAA.Saphihr:BAAALgADCgYJBgAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAEAAAAAA==.',
Se='Sedo:BAABLgAECn8UAAIFAAYJbAO1/ACtAAAFAAYJbAO1/ACtAAAAAA==.Selenis:BAAALgAECgcJDQABLgAECgkJNwAGAJolAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowmonarc:BAAALgAECgYJCwAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shamainiac:BAABLgAECn9HAAIDAAkJ8hguEwBRAgADAAkJ8hguEwBRAgAAAA==.Shamith:BAAALgAECgcJDgAAAA==.Shammymax:BAAALgADCgkJAQAAAA==.Shaomai:BAACLgAFFH8LAAIDAAQJyhcBIwAIAQADAAQJyhcBIwAIAQAuAAQKfysAAwMACQn1IM4KALECAAMACQn1IM4KALECAAIABAkvDRpzAMMAAAAA.Sharper:BAACLgAFFH8KAAIdAAQJ4xqjNwA+AQAdAAQJ4xqjNwA+AQAuAAQKfxcAAh0ABwlpHFhNAJoBAB0ABwlpHFhNAJoBAAEuAAUUBAkOABkAnxgA.Shep:BAAALgAECgMJAwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shi:BAAALgAECgQJBAAAAA==.Shifte:BAAALgAECggJDgAAAA==.Shiok:BAAALgAECgMJAwAAAA==.Shishkademon:BAAALgAECgIJAgAAAA==.Shoknorris:BAAALgADCgkJCQAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgcJDAAAAA==.Silverwin:BAABLgAECn8qAAIWAAgJhA8SLQBeAQAWAAgJhA8SLQBeAQAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8lAAIoAAkJRRpIAgA7AgAoAAkJRRpIAgA7AgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJDgAAAA==.Smitted:BAABLgAECn8ZAAMIAAcJ5A5zsAAcAQAIAAcJlwtzsAAcAQAOAAYJ3QpXIwDtAAAAAA==.Smitty:BAABLgAECn8VAAMBAAgJnhVBIgCVAQABAAgJeBRBIgCVAQApAAgJQxBTLABaAQAAAA==.',
Sn='Snakmag:BAAALgAECgEJAQAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAABLgAECn8YAAMhAAYJWBRwNAB+AQAhAAYJWBRwNAB+AQAIAAYJMQ4HyAD7AAAAAA==.Sophiaa:BAAALgADCgcJBgAAAA==.Sorn:BAABLgAECn8zAAIOAAkJRBG9EAC0AQAOAAkJRBG9EAC0AQAAAA==.',
Sp='Spaarkle:BAAALgAECggJDwAAAA==.Specialheist:BAABLgAECn8bAAIWAAkJ1QKhSQC5AAAWAAkJ1QKhSQC5AAAAAA==.Spectrehawk:BAAALgAECgYJDAABLgAFFAQJFgAGANQjAA==.Speçtre:BAACLgAFFH8WAAIGAAQJ1CMtDQChAQAGAAQJ1CMtDQChAQAuAAQKfy8AAwYACQkNHRQLAF0CAAYACAk0IBQLAF0CABkAAQn+Bi9fAT0AAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgQJBAAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAABLgAECn8aAAIXAAgJGBboIAC9AQAXAAgJGBboIAC9AQAAAA==.Stormglaive:BAABLgAECn8aAAMcAAcJPxU8HQDWAQAcAAcJPxU8HQDWAQAdAAEJUwPt6QAoAAAAAA==.Strikedark:BAAALgAECgEJAQAAAA==.Stupidity:BAABLgAECn8sAAMXAAgJeB4MEwA5AgAXAAgJeB4MEwA5AgAWAAIJhBdZVwB3AAAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn9HAAMRAAkJ3x/JBwAdAwARAAkJ3x/JBwAdAwApAAgJRhRLIQChAQAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
Sy='Synterra:BAAALgADCgkJCQAAAA==.Syranda:BAAALgAFFAEJAQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgAECgEJAQABLgAECgkJQQAFAL8jAA==.Tarysha:BAABLgAECn8qAAIkAAkJvwnAHACsAQAkAAkJvwnAHACsAQAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn80AAIgAAkJ5xAlHgBWAQAgAAkJ5xAlHgBWAQAAAA==.Tayoma:BAAALgAECgEJAwAAAA==.Tazara:BAAALgAECgQJBQAAAA==.',
Te='Tealth:BAAALgAECgYJBgAAAA==.Ted:BAABLgAECn8kAAIDAAgJghbIJAC+AQADAAgJghbIJAC+AQAAAA==.Tehgermza:BAAALgAECgcJBwAAAA==.Tehgrimza:BAABLgAECn8pAAMfAAkJ1xmwHgBrAgAfAAkJ1xmwHgBrAgAiAAEJrxCDdAAwAAAAAA==.Teias:BAAALgAECggJCgABLgAFFAUJFAAWAEUaAA==.Teka:BAAALgADCgMJAwAAAA==.Temu:BAAALgAECgYJCAABLgAFFAQJCQAfABAXAA==.Tet:BAACLgAFFH8HAAINAAMJAQ+TQgCjAAANAAMJAQ+TQgCjAAAuAAQKfxkAAg0ACAkyH2cQAMwCAA0ACAkyH2cQAMwCAAAA.Tevia:BAABLgAECn8tAAIQAAkJ4xhGDQAQAgAQAAkJ4xhGDQAQAgAAAA==.',
Th='Thalip:BAAALgAECgQJBwAAAA==.Thekingheals:BAAALgAECgUJCAABLgAFFAMJBgApAEkZAA==.Thokmay:BAABLgAECn8pAAIpAAkJZxG0HwCrAQApAAkJZxG0HwCrAQAAAA==.Thorel:BAAALgAECgQJBAAAAA==.Thornar:BAAALgAECgUJBQAAAA==.Thunden:BAAALgAECgYJCwAAAA==.Thyeth:BAAALgADCgEJAQAAAA==.',
Ti='Tiandrinna:BAABLgAECn8qAAIMAAkJKxxGAgA/AgAMAAkJKxxGAgA/AgAAAA==.Tightywhitey:BAAALgAECggJDwAAAA==.Timkaoss:BAABLgAECn8dAAMNAAYJtBf8VQA1AQANAAYJtBf8VQA1AQAKAAMJNQfIewBLAAAAAA==.Timmyjudge:BAAALgAECgYJCAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAABLgAECn8qAAILAAgJowaoJwDyAAALAAgJowaoJwDyAAAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgkJFgAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgQJCAABLgAECgkJLQACALMiAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgAECgUJEAAAAA==.Trixterwolf:BAAALgADCgUJBwAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAACLgAFFH8LAAIFAAMJ7xAKfQDjAAAFAAMJ7xAKfQDjAAAuAAQKfy0AAgUACQlcGUY7ACoCAAUACQlcGUY7ACoCAAAA.',
Ty='Tygrassar:BAAALgAECgIJAgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8wAAIWAAkJVh25CADbAgAWAAkJVh25CADbAgAAAA==.',
['Tä']='Täd:BAABLgAECn8XAAIfAAYJ/RE3iQAnAQAfAAYJ/RE3iQAnAQAAAA==.',
Un='Unholycreep:BAAALgAFFAEJAQABLgAFFAQJCQALAGwcAA==.',
Va='Vaelenka:BAAALgADCgMJAwAAAA==.Vaelune:BAAALgAECgYJBgAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAABLgAECn8jAAMHAAgJ9Qv6EgBGAQAHAAgJXAv6EgBGAQAZAAYJPAk5zADqAAAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAACLgAFFH8GAAIIAAMJlQ9ccADLAAAIAAMJlQ9ccADLAAAuAAQKfyIAAggACAlXHsY7ABICAAgACAlXHsY7ABICAAAA.Valicous:BAAALgAECgUJDgAAAA==.Valyerian:BAABLgAECn8uAAIUAAgJ5hsOFgCcAgAUAAgJ5hsOFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgkJHgAGAGMiAA==.Vandevoker:BAAALgAECgQJCAABLgAECgkJHgAGAGMiAA==.Vanserra:BAAALgADCgcJEAAAAA==.Varregory:BAAALgADCgUJBAAAAA==.Vaxas:BAABLgAECn8jAAIIAAgJ1h/OMQA2AgAIAAgJ1h/OMQA2AgAAAA==.Vaxasus:BAAALgAECgEJAQAAAA==.Vaylorian:BAABLgAECn8VAAIgAAYJFyB+EgDDAQAgAAYJFyB+EgDDAQAAAA==.Vaült:BAABLgAECn85AAMhAAkJ8hhODwCgAgAhAAkJ8hhODwCgAgAIAAMJPwYbEgFzAAAAAA==.',
Ve='Velystana:BAAALgADCgIJAgAAAA==.Verianna:BAABLgAECn83AAQGAAkJmiUyAQBUAwAGAAkJFSUyAQBUAwAZAAgJZyFMLwA/AgAHAAUJlhoiDwCAAQAAAA==.Vexmorphis:BAAALgAECgMJBAABLgAECgkJHgAIAJwSAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgAECgQJBAAAAA==.',
Vr='Vraknaar:BAAALgAECgMJAwAAAA==.',
Vt='Vtown:BAAALgAECgMJBgAAAA==.',
Wa='Wadumu:BAABLgAECn8xAAMNAAgJXAwOaQAYAQANAAYJVg4OaQAYAQAgAAgJlwvtLQDwAAAAAA==.Wagwanmist:BAABLgAECn8tAAIRAAgJtBkAHQArAgARAAgJtBkAHQArAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warrdaddy:BAAALgAECgIJAwAAAA==.Warvegas:BAAALgAECgUJDAAAAA==.Warwulf:BAAALgAECgQJBAABLgAECggJJQAUADwcAA==.Water:BAAALgADCgEJAQAAAA==.',
Wi='Willowy:BAABLgAECn9BAAIFAAkJvyOuCgAiAwAFAAkJvyOuCgAiAwAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8cAAQCAAUJ4hNWdgD1AAACAAUJ4hNWdgD1AAADAAQJ6wh1ewB3AAAjAAEJngrjPQAxAAAAAA==.',
Xa='Xaerius:BAABLgAECn9HAAMUAAkJEBo7EgBgAgAUAAkJEBo7EgBgAgAQAAEJ6wUlgwAjAAAAAA==.Xalatath:BAAALgAECgUJBQAAAA==.Xan:BAABLgAECn8gAAIFAAkJyRdkUADnAQAFAAkJyRdkUADnAQAAAA==.Xann:BAAALgAECgIJAgAAAA==.Xannen:BAAALgADCgkJCQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAABLgAECn8YAAMFAAgJ4yCnIgCQAgAFAAgJ6h+nIgCQAgAoAAIJyCDICwC9AAAAAA==.Xashadin:BAAALgAECgcJBwAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIFAAcJJiNIPQCCAgAFAAcJJiNIPQCCAgAAAA==.',
Xo='Xog:BAAALgAECgIJAgAAAA==.',
Ya='Yarman:BAABLgAECn8qAAIBAAgJBRToHQC0AQABAAgJBRToHQC0AQAAAA==.',
Ye='Yeaforpie:BAABLgAECn8hAAMfAAkJvg5FXACJAQAfAAgJuw9FXACJAQAnAAYJvQwDGAD/AAAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAABLgAECn8YAAIhAAgJ7BRkKwCzAQAhAAgJ7BRkKwCzAQAAAA==.',
Yo='Yoshial:BAABLgAECn8aAAIFAAYJ0wcA2ADiAAAFAAYJ0wcA2ADiAAAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAABLgAECn81AAMXAAkJThajGAAAAgAXAAkJThajGAAAAgAYAAYJPA0AQQAFAQAAAA==.',
Ze='Zealins:BAAALgAECgQJBAAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zerastar:BAAALgAECgQJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQABLgAFFAUJEwAIAOskAA==.Zirou:BAAALgAFFAEJAQABLgAFFAMJCAAeACMhAA==.Ziv:BAACLgAFFH8RAAINAAQJwB4hHgBgAQANAAQJwB4hHgBgAQAuAAQKfzYAAg0ACQkqIKYIACsDAA0ACQkqIKYIACsDAAEuAAUUAwkIAB4AIyEA.Ziyn:BAACLgAFFH8IAAIeAAMJIyERFwAVAQAeAAMJIyERFwAVAQAuAAQKfxgAAx4ACQk+Hj4HAKsCAB4ACQk+Hj4HAKsCAAkABgmuGvN6AEQBAAAA.',
Zo='Zoda:BAAALgAECgIJAwAAAA==.',
Zx='Zxno:BAAALgAECgEJAQAAAA==.',
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
